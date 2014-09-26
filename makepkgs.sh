#!/bin/bash

[[ -z ${PATH} ]] && PATH=/usr/bin

show_help () {
cat <<END_OF_SHOW_HELP
${0} <OPTIONS>

FLAGS THAT ONLY MAKE SENSE BY THEMSELVES:

As soon as the program sees one of these options, all command line
argument processing stops.

  -h  Show this help
  -l  Only list package info. 
  -d  Only reconstruct repo database.
  -s  Only sign packages.

COMBINABLE FLAGS:

  -c  <CHROOT-DIR> Chroot directory for makechrootpkg.  Program will
                   append \$arch to this value.  Default is /srv/build.
                   Program will build i686 packages in <CHROOT-DIR>/i686
                   and build x86_64 packages in <CHROOT-DIR>/x86_64.

  -i               Prints extra information.  (Not exactly verbose.)

  -n  <REPO-NAME>  Repository name.  Will be appended to <REPO-DIR>.

  -p               Use plain text instead of colorized text.

  -r  <REPO-DIR>   Repository directory.  Default is /srv/repo.
                   Will be appended with <REPO-NAME>.

  -u  <USERNAME>   User to run package signing as.  Defaults to \$USER,
                   which retains orignal user name even with privilege
                   escalation with su.
  
  -f  Update RSS   Update an RSS feed

END_OF_SHOW_HELP
} 
 
### CONSTANTS & SHORTCUTS ###

COLOR='\e[1;35m'
BEGIN='\e[1;32m'
RESET='\e[0m'
TAB1='tput cub 80; tput cuf 30'
TAB2='tput cub 80; tput cuf 55'
TAB3='tput cub 80; tput cuf 80'

### GLOBAL VARIABLES ###

NEWPKS=""
BADPKS=""
FLAG_MAKE=true  # Make packages?
FLAG_LIST=false # Only list package info?
FLAG_REPO=false # Only update the repos?
FLAG_SIGN=false # Only sign packages?
FLAG_URSS=false # Update the RSS feed?
FLAG_INFO=false # Print a little more info?

### SET VARIABLES BASED ON PARAMETERS ###

OPTIND=1

while getopts "hildsfpc:r:n:u:" opt; do
  case "${opt}" in
    '?')  show_help >&2 && exit 1;;
    h) show_help && exit 0;;
    l) FLAG_LIST=true ; FLAG_MAKE=false ; break ;;
    d) FLAG_REPO=true ; FLAG_MAKE=false ; break ;;
    s) FLAG_SIGN=true ; FLAG_MAKE=false ; break ;;
    f) FLAG_URSS=true ; FLAG_MAKE=true ;;
    i) FLAG_INFO=true   ;;
    c) CHROOT=${OPTARG} ;;
    r) REPDIR=${OPTARG} ;;
    n) REPNAM=${OPTARG} ;;
    u) USRNAM=${OPTARG} ;;
    p) COLOR='' ; BEGIN='' ; RESET='' ;;
  esac
done

shift $((OPTIND-1))

### CHECK TO SEE IF RUN AS ROOT ###

[[ ${EUID} -eq 0 && ! ${FLAG_MAKE} ]] &&
  echo "This script must be run as root when making packages." >&2 && exit 1

### CHECK TO SEE IF WE ARE ALREADY RUNNING ###

if [ -f /var/run/lock/makepkgs.lock ]; then
  echo "Lock file /var/run/lock/makepkgs.lock detected.  Is the script already running?" >&2 
  [ -t 1 ] && echo "This file may be left behind if the script crashes or is interrupted"
  [ -t 1 ] && echo "If you are sure that this script is not running please delete the lock file."
  exit 1
else
  touch /var/run/lock/makepkgs.lock
fi

### TELL USER ABOUT FALLING BACK TO DEFAULTS ###

[ -z ${CHROOT} ] && CHROOT="/srv/build" && $FLAG_INFO && [ -t 1 ] && echo "No chroot directory specified, defaulting to /srv/build" 
[ -z ${REPDIR} ] && REPDIR="/srv/repo" && $FLAG_INFO && [ -t 1 ] && echo "No repo directory specified, defaulting to /srv/repo"
[ -z ${USRNAM} ] && USRNAM="${USER}" && $FLAG_INFO && [ -t 1 ] && echo "No username specified.  Will sign packages as ${USER}"

### MAKE SURE WE HAVE THE REQUISITE BINARIES ###

for binary in sed tar xz wget arch-nspawn makechrootpkg; do
  type ${binary} > /dev/null 2>&1 || { echo "${binary} is not installed." >&2; exit 1; }
done

### MAKE SURE A REPO NAME WAS SPECIFIED ###

[ -z ${REPNAM} ] && echo "No repo name specified" >&2 && show_help >&2 rm /var/run/lock/makepkgs.lock && exit 1


### MAKE SURE THE BUILD CHROOTS EXISTS ###

for arch in x86_64 i686; do
  if [ ! -d "${CHROOT}/${arch}/root" ]; then
    echo "${CHROOT}/{$arch}/root does not exist.  Does ${CHROOT} contain chroots for building?" >&2
    exit 1
  fi
done

### CHECK TO SEE IF WE HAVE A WORKING INTERNET CONNECTION ###

! host aur.archlinux.org &> /dev/null && \
  echo "Can't find host info for aur.archlinx.org.  Is your network up?  Is the site down?" && exit 1

### TEST IF AUR IS RESPONDING PROPERLY -- DEPENDS ON testpkg ###

  tstpkg=$(cat ${REPDIR}/testpkg | cut -f1)
  tstver=$(cat ${REPDIR}/testpkg | cut -f2)

  aurtst=$(wget -qO - "https://aur.archlinux.org/rpc.php?type=info&arg=${tstpkg}" | \
           sed 's/[,{]/\n/g' | grep "Version" | cut -d\" -f4)

  [[ ${aurtst} != ${tstver} ]] && echo "Unexpected query result from the AUR for the ${tstpkg} package." && exit 1

### FUNCTIONS ###

function message() {
  [ -t 1 ] && echo -e "${COLOR}${1}${RESET}"
}

function system_update () {
  cmd1="pacman -Sc --noconfirm > /dev/null;"
  cmd2="pacman -Syu --noconfirm"
  [ -t 1 ] && message "${1}: Purging non-installed packages, refreshing repos, and updating system."
  eval arch-nspawn ${CHROOT}/${1}/root "${cmd1}"
  eval arch-nspawn ${CHROOT}/${1}/root "${cmd2}"
}

function pkg_ver_comp () {
  [ ! $(echo -e "${1}\n${2}" | sort --version-sort | head -1) = "${2}" ]
}

function pkg_ver_loc () {
  lpkgnam=`ls ${REPDIR}/${REPNAM}/${2}/${1}-[0-9rl]*.pkg.tar.xz 2> /dev/null | head -1 | rev | cut -d/ -f1 | rev`
  lpkgver=`echo ${lpkgnam:\`expr ${#1} + 1\`:\`expr ${#lpkgnam} - ${#1} - 12\`} | rev | cut -d- -f2- | rev`
  [[ "${lpkgnam}" == "" ]] && lpkgver='missing'
  echo ${lpkgver}
}

function pkg_ver_aur () {
   result=$(wget -qO - "https://aur.archlinux.org/rpc.php?type=info&arg=${1}" | \
            sed 's/[,{]/\n/g' | grep "Version" | cut -d\" -f4)
   [[ -n ${result} ]] && echo ${result} || echo "missing"
}

function pkg_get () {
  wget -q https://aur.archlinux.org/packages/${1:0:2}/${1}/${1}.tar.gz
  tar -zxvf ${1}.tar.gz > /dev/null
  rm ${1}.tar.gz
}

function pkg_remove() {
  [ -t 1 ] && message "Removing ${1}-${2} from ${3}..."
  eval rm -rv "${REPDIR}/${REPNAM}/${3}/${1}-${2}-*.pkg.tar.xz*"
}

function pkg_add () {
  # A bit hackish since some git builds will change pkg version after makepkg
  # The only guarantee left is that there will a single package inside ${1}
  message "Moving ${1} package to repo..."
  mv -v ${REPDIR}/${REPNAM}/build/aur/${1}/*.pkg.tar.xz ${REPDIR}/${REPNAM}/${2}
}

function repo_build() {
  message "Updating repo database for ${1}..."
  rm ${REPDIR}/${REPNAM}/${1}/${REPNAM}.db*
  if [ ${EUID} == `id -u ${USRNAM}` ]; then
    repo-add -q ${REPDIR}/${REPNAM}/${1}/${REPNAM}.db.tar.xz ${REPDIR}/${REPNAM}/${1}/*.pkg.tar.xz
  else
    su -c "repo-add -q ${REPDIR}/${REPNAM}/${1}/${REPNAM}.db.tar.xz ${REPDIR}/${REPNAM}/${1}/*.pkg.tar.xz" - ${USRNAM}
  fi
}

function sign_pkgs() {
  message "Signing packages with missing signatures for ${1} as ${USRNAM}..."
  for file in ${REPDIR}/${REPNAM}/${1}/*.pkg.tar.xz; do
    if [ ! -e ${file}.sig ]; then
      [ -t 1 ] && echo "Signing ${file}..."
      if [ ${EUID} != `id -u ${USRNAM}` ]; then
        su -c "gpg --detach-sign ${file}" - ${USRNAM}
      else
        gpg --detach-sign ${file}
      fi
    fi
  done
}

function pkg_build () {

  message "Preparing to build ${1} for ${4}..."
  rm -rf ${REPDIR}/${REPNAM}/build/aur/${1}

  mpec=1
  pkg_get ${1}

  trch="`cat ${REPDIR}/${REPNAM}/build/aur/${1}/PKGBUILD | grep arch= | cut -d= -f2`"
  tnat="`echo ${trch} | grep ${4}`"
  tany="`echo ${trch} | grep any`"

  if [ -n "${tany}" -a "${4}" == "i686" ]; then
    message 'ANY package detected, will copy x86_64 version.'
    cp ${REPDIR}/${REPNAM}/x86_64/${1}* ${REPDIR}/${REPNAM}/i686/
    [[ "${2}" != "missing" ]] && pkg_remove ${1} ${2} ${4}
  else
    if [ -n "${tnat}" -o -n "${tany}" ]; then
      chown -R nobody ${REPDIR}/${REPNAM}/build/aur/${1}
      cd ${REPDIR}/${REPNAM}/build/aur/${1}
      [[ -f ../${1}.sh ]] && message 'Executing PKGBUILD customization...' && sh ../${1}.sh
      makechrootpkg -cur ${CHROOT}/${4} -l aurpbs
      if [ $? == 0 ]; then
        message 'Package creation succeeded!'
        if [ -f "`ls ${REPDIR}/${REPNAM}/build/aur/${1}/${1}-*.pkg.tar 2> /dev/null`" ]; then 
          message 'Package left as tarball.  Manually compressing...'
          xz ${REPDIR}/${REPNAM}/build/aur/${1}/${1}-*.pkg.tar
        fi 
        [[ "${2}" != "missing" ]] && pkg_remove ${1} ${2} ${4}
        pkg_add ${1} ${4}; sign_pkgs ${4}; repo_build ${4}; system_update ${4};
        NEWPKS="${NEWPKS}${1} for ${4}"$'\n'
         cd ${REPDIR}/${REPNAM}/build
      else
        message 'Package creation failed!'
        BADPKS="${BADPKS}${1} for ${4}"$'\n'
      fi
      cd ${REPDIR}/${REPNAM}/build/aur
    else
      [ -t 1 ] && echo -e "\e[1;31mPACKAGE ${1} not intended for ${4}.${RESET}"
    fi
    rm -rf ${REPDIR}/${REPNAM}/build/aur/w${1}
  fi
  return ${mpec}
}

function pkg_search () {
  pmsrch=`pacman -Ss ${1} | grep ${1} | grep -v ${REPNAM} | cut -f1 -d/`
  if [ "${pmsrch}" == "" ]; then
    [ -t 1 ] && echo -e "${COLOR}Inv Pkg${RESET}"
  else
    message "${1} is now in ${pmsrch:0:10}"
    [[ "${2}" != "missing" ]] && pkg_remove ${1} "${2}" "${3}"
  fi
}

${FLAG_SIGN} && { sign_pkgs x86_64; sign_pkgs i686; exit 0; }
${FLAG_REPO} && { repo_build x86_64; repo_build i686; exit 0; }
${FLAG_LIST} || { system_update x86_64 && system_update i686; }

### MAKE SURE WE HAVE A PAKCAKGE LIST ###

if [ -f "${REPDIR}/${REPNAM}/build/aur/packages.list" ]; then

  ### CREATE DIRECTORIES IF THEY DON'T EXIST ###

  mkdir -p ${REPDIR}/${REPNAM}/build/aur
  mkdir -p ${REPDIR}/${REPNAM}/{x86_64,i686}

  if [ -t 1 ]; then 
    echo -e "${BEGIN}*** STARTING WITH REPO ${REPNAM} ***${RESET}\n"
    echo -ne "PACKAGE NAME"; eval ${TAB1}
    echo -ne "LCL X86_64 VER"; eval ${TAB2}
    echo -ne "LCL I686 VER"; eval ${TAB3}
    echo -e  "AUR VERSION"
  fi

  while read line; do
    depupd=0

    for pkg in ${line}; do
      [[ "${pkg:0:1}" == "#" ]] && break
      cd ${REPDIR}/${REPNAM}/build/aur
      lvx=$(pkg_ver_loc ${pkg} x86_64); lvi=$(pkg_ver_loc ${pkg} i686)
      if [ ${depupd} == 1 ]; then
        message "Dependency of ${pkg} updated.  Clearing out for rebuild..."
        pkg_remove ${pkg} \* "{x86_64,i686}"
        repo_build x86_64; repo_build i686
        system_update x86_64; system_update i686
        lvx=$(pkg_ver_loc ${pkg} x86_64); lvi=$(pkg_ver_loc ${pkg} i686)
      fi
      if [ -t 1 ]; then 
        echo -ne "${COLOR}${pkg}${RESET}"; eval $TAB1
        echo -ne "${COLOR}${lvx}${RESET}"; eval $TAB2
        echo -ne "${COLOR}${lvi}${RESET}"; eval $TAB3
      fi
      av=$(pkg_ver_aur ${pkg})
      [ -t 1 ] && echo -e "${COLOR}${av}${RESET}"
      if [ ${av} == missing ]; then
        pkg_search ${pkg} \* "{x86_64,i686}"
        message "Removing ${1} from the repos..."
        rm -rf "${REPDIR}/${REPNAM}/build/aur/${pkg}" 2> /dev/null
      else
        for arch in x86_64 i686; do
          [ $arch == x86_64 ] && lvl=${lvx} || lvl=${lvi}
          if [ ${lvl} == missing ]; then
            if [ ${FLAG_LIST} == false ]; then
              pkg_build ${pkg} ${lvl} ${av} ${arch} && [[ $? == 0 ]] && depupd=1
            else
              $FLAG_INFO && [ -t 1 ] && echo "List mode on...not building missing ${arch} package."
            fi
          else 
            if pkg_ver_comp ${lvl} ${av}; then
              if [ ${FLAG_LIST} == false ]; then
                pkg_build ${pkg} ${lvl} ${av} ${arch} && [[ $? == 0 ]] && depupd=1
              else
                [ -t 1 ] && echo "List mode on...not building out-of-date ${arch} package."
              fi
            fi
          fi
        done
      fi
    done
  done < "${REPDIR}/${REPNAM}/build/aur/packages.list"
else
  echo "${REPDIR}/${REPNAM}/build/aur/packages.list does not exist." >&2
  exit 1
fi

[ -t 1 ] && echo -e "\n${BEGIN}*** FINISHED WITH REPO ${REPNAM} ***${RESET}\n"

if [ ! ${FLAG_URSS} ]; then

  # This section relies on BrainwreckedRSS 
  # Visit rss.bw-tech.net for more information

  cd ${REPDIR}/bwrss

  [[ "$NEWPKS" != "" ]] && 
    NEWPKS=$(echo "$NEWPKS" | sed ':a;N;$!ba;s/\n/\&lt;br\/\&gt; /g') &&
    php update.php aurpb "New Packages Built" "AURPB Build Script" "${NEWPKS} &lt;br /&gt;Packages are waiting production."

  [[ "$BADPKS" != "" ]] && 
    BADPKS=$(echo "$BADPKS" | sed ':a;N;$!ba;s/\n/\&lt;br\/\&gt; /g') &&
    EXCUSE="Common reasons: Dependencies broken, source dl link broken, AUR maintainer broken." 
    php update.php aurpb "Failed Packages" "AURPB Build Script" "${BADPKS} &lt;br /&gt;${EXCUSE}"
fi

rm /var/run/lock/makepkgs.lock
exit 0

