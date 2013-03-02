#!/bin/sh

### CONSTANTS & SHORTCUTS ###

clr='\e[1;35m'
rst='\e[0m'
tb1='tput cub 80; tput cuf 28'
tb2='tput cub 80; tput cuf 49'
tb3='tput cub 80; tput cuf 70'
arch=`lscpu | grep Architecture | cut -d: -f2 | sed 's/\s*//g'`

### CONFIGURATION ###

repdir=[dir]
repnsm=[name]
rmuser=[user]
rmhost=[host]
rmport=[port]
rmport=[path]

### SANITY CHECKS ###

# Check for wget
# Check for gpg
# Check for $repdir/$repnms/aur/packages.list

function pkg_ver_loc () {
  lpkgnam=`ls $repdir/$repnms/$arch/${1}-*.pkg.tar.xz 2> /dev/null | head -1 | rev | cut -d/ -f1 | rev`
  lpkgver=`echo ${lpkgnam:\`expr ${#1} + 1\`:\`expr ${#lpkgnam} - ${#1} - 12\`} | rev | cut -d- -f2- | rev`
  [[ "$lpkgnam" == "" ]] && lpkgver='missing'
  echo $lpkgver
}

function pkg_ver_aur () {
  wget -q -O ${1}.info "https://aur.archlinux.org/rpc.php?type=info&arg=${1}"
  sed -i 's/[,{]/\n/g' ${1}.info
  result=`cat ${1}.info | grep "resultcount" | cut -d\: -f2`
  [[ $result == 0 ]] && pkgver="missing"
  [[ $result != 0 ]] && pkgver=`cat ${1}.info | grep "Version" | cut -d\" -f4`
  rm ${1}.info
  echo $pkgver
}

function pkg_get () {
  wget -q https://aur.archlinux.org/packages/${1:0:2}/${1}/${1}.tar.gz
  tar -zxvf ${1}.tar.gz > /dev/null
  rm ${1}.tar.gz
}

function pkg_remove() {
  repo-remove -v -s $repdir/$repnms/$arch/${repnms}.db.tar.xz $1
  rm $repdir/$repnms/$arch/${1}-${2}-*.pkg.tar.xz*
}

function pkg_add () {
  # A bit hackish since some git builds will change pkg version after makepkg
  # The only guarantee left is that there will a single package inside $1
  pkgfil=`ls -1 $repdir/$repnms/build/aur/${1}/${1}-*.pkg.tar.xz`
  repo-add -v -s $repdir/$repnms/$arch/${repnms}.db.tar.xz $pkgfil
  mv ${pkgfil} $repdir/$repnms/$arch
  mv ${pkgfil}.sig $repdir/$repnms/$arch
  sudo pacman -Sy
}

function pkg_build () {
  pkg_get $1

  trch="`cat $repdir/$repnms/build/aur/$1/PKGBUILD | grep arch= | cut -d= -f2`"
  tnat="`echo $trch | grep $arch`"
  tany="`echo $trch | grep any`"

  if ! [ -z $tnat -a -z $tany ]; then
    cd $repdir/$repnms/build/aur/$1
    [[ -f ../${1}.sh ]] && sh ../${1}.sh
    makepkg -sc --sign --noconfirm; mpec=$?
    [[ $mpec != 0 ]] && makepkg -sc --sign && mpec=$?
    if [ $mpec == 0 ]; then
      echo -e ${clr}Package creation succeeded!${rst}
      if [ -f "`ls $repdir/$repnms/build/aur/${1}/${1}-*.pkg.tar`" ]; then 
        echo -e "${clr}Package left as tarball.  Manually compressing and signing...${rst}"
       xz -9 $repdir/$repnms/build/aur/${1}/${1}-*.pkg.tar
        gpg --detach-sign $repdir/$repnms/build/aur/${1}/${1}-*.pkg.tar.xz 
      fi 
      [[ "$2" != "missing" ]] && pkg_remove $1 $2
      pkg_add $1 $3
      sudo pacman -Sy; cd $repdir/$repnms/build; rm -r $repdir/$repnms/build/aur/$1
    else
      echo -e ${clr}Package creation failed!${rst}
      rm -r $repdir/$repnms/build/aur/$1
    fi
  else
    echo -e "\e[1;31mPACKAGE $1 not intended for $arch.${rst}"
  fi
}

function pkg_search () {
  pmsrch=`pacman -Ss ${1} | grep ${1} | grep -v $repnms | cut -f1 -d/`
  if [ "$1" == "" ]; then
    echo -e "Inv Pkg${rst}"
  else
    echo -e "${pmsrch:0:10}${rst}"
    [[ "$2" != "missing" ]] && pkg_remove $1 $2
  fi
}

echo -ne PACKAGE NAME; eval $tb1
echo -ne LOCAL VERSION; eval $tb2
echo -ne AUR VERSION; eval $tb3
echo STATUS

for pkg in `cat $repdir/$repnms/build/aur/packages.list | sed 's/#.*//g'`; do
  if [ "${package:0:1}" != "!" ]; then
    if ! [[ $arch == i686 && ${pkg:0:5} == lib32 ]]; then
      cd $repdir/$repnms/build/aur
      echo -ne ${clr}${pkg:0:27}${rst}; eval $tb1
      lv=$(pkg_ver_loc ${pkg}); echo -ne ${clr}$lv${rst}; eval $tb2
      av=$(pkg_ver_aur ${pkg}); echo -ne ${clr}$av${rst}; eval $tb3
      if [ $av == missing ]; then
        pkg_search $pkg $lv
      else
        if [ $lv == missing ]; then
         echo -e ${clr}Missing${rst} && pkg_build $pkg $lv $av
        else
          [[ $lv < $av ]] && echo -e ${clr}Outdated${rst} && pkg_build $pkg $lv $av
          [[ $lv == $av ]] && echo -e ${clr}Current${rst}
          [[ $lv > $av ]] && echo -e ${clr}Indated${rst}
        fi
      fi
    fi
  fi
done

rsync --progress --del -avze "ssh -p $rmport" /$repdir/$repnms/$arch/ ${rmuser}@${rmhost}:${rmpath}
