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
    contains the scripts
* /srv/repo/[name]
    for each repositiory you want
* /srv/repo/[name]/aur
    temp space for buiding from the AUR
* /srv/repo/[name]/aur/packages.list
    which packages you want to build
    can list multiple packages per line -- useful for dependencies
* /srv/repo/[name]/aur/[package-name].sh
    Sometimes AUR packages need a little help
    The .sh is a standard shelll script that can do anything you want 

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
