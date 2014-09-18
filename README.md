AUR Builder Script
==================

These scripts will build a set of packages from the AUR and create a
repository.  It checks to see if you already have the package built.
If so, it will check the local version against the version from the AUR.
If the package is not built locally or is out-of-date compared to the AUR,
it will build the package and sign it.

LIMITATION: Version numbers can be auto-bumped by PKGBUILD's built-in
package versioning for code retrieved from git & svn.  This script, at
this time, only checks the version as reported by the AUR.

Directory Setup
---------------

First you will need some directories.
By default, the script use /srv/repo.

* /srv/repo
  - contains the scripts
* /srv/repo/[name]
  - for each repositiory you want
* /srv/repo/[name]/aur
  - temp space for buiding from the AUR
* /srv/repo/[name]/aur/packages.list
  - which packages you want to build
  - can list multiple packages per line -- useful for dependencies
* /srv/repo/[name]/aur/[package-name].sh
  - Sometimes AUR packages need a little help
  - The .sh is a standard shelll script that can do anything you want 

Chroot Setup
------------

The script uses chroots for clean builds and to prevent headaches that may 
occur from repeatedly installing and removing packages in bulk on your system.

By default, the script uses /srv/build.

You should have one chroot for each $arch.
Using defaults, you should have a /srv/build/i686 and /srv/build/x86_64.

For building your x86_64 chroot:
https://wiki.archlinux.org/index.php/DeveloperWiki:Building_in_a_Clean_Chroot#Classic_Way

For building your i686 chroot:
https://wiki.archlinux.org/index.php/Building_32-bit_packages_on_a_64-bit_system

For each chroot, you will want to setup pacman.conf to reference your repository.

Additional Setup Notes
----------------------

Be sure you build dependencies first!  The best way to catch dependencies is to go to the AUR package's page and hover over the links in the dependency section.  If the link points to www.archlinux.org, the dependency is in the official repos.  If the link points to aur.archlinux.org, you will have to build that package before you can build the package you want.  As is standard in Linux, dependencies can get quite deep.

There is a bit of a race condition when building a repo for the first time.  If you correctly set up your new repo in the chroot first, it will fail to retreive the non-existent repo database.  If any package requires installing dependencies, this will cause the build process to fail becauase pacman will return an error code.  This can be resolved in two ways:

* Make your first package one that does not have any dependencies.
* Set up your new repo in the chroots AFTER building ONE package successfully.

It is generally a good idea to keep "staging" and "production" versions of your repo.  Keep your chroots to pointed to the staging version and clients pointed at a seperate production version.  When all goes well in staging, copy new files to production first, then the new database files, followed by deletion of old files.  If something goes awry and packages get borked, copy them back over from production instead of building new ones.

