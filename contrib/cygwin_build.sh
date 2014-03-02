#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming the following packages are installed:
# - dos2unix
# - make
# - curl
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit)
# - mingw-gcc-g++ (for 32 bit)
# - mingw-gcc-fortran (for 32 bit)
#
# This script is intended to be executed from the base julia directory as contrib/cygwin_build.sh

dos2unix contrib/relative_path.sh deps/jldownload 2>&1

if [ `arch` = x86_64 ]; then
  echo "XC_HOST = x86_64-w64-mingw32" > Make.user
else
  echo "XC_HOST = i686-pc-mingw32" > Make.user
fi

make -C deps getall > get-deps.log 2>&1
dos2unix */*/configure 2>&1
make
