#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming the following packages are installed:
# - dos2unix
# - make
# - wget
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit)
# - mingw-gcc-g++ (for 32 bit)
# - mingw-gcc-fortran (for 32 bit)
#
# This script is intended to be executed from the base julia directory as contrib/cygwin_build.sh

# stop on error
set -e

git config --global user.email "appveyor@julialang.org"
git config --global user.name "Julia AppVeyor"
echo "* text=auto" >>.gitattributes
rm .git/index     # Remove the index to force git to
git reset         # re-scan the working directory
#git status        # Show files that will be normalized
git add -u
git add .gitattributes
git commit -m "Introduce end-of-line normalization"

#dos2unix contrib/relative_path.sh deps/jldownload

if [ `arch` = x86_64 ]; then
  XC_HOST=x86_64-w64-mingw32 make
else
  XC_HOST=i686-pc-mingw32 make
fi
