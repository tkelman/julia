#!/bin/sh

# stop on failure
set -e
uname -a
sudo apt-get install g++-mingw-w64-i686 gfortran-mingw-w64-i686
echo 'XC_HOST = i686-w64-mingw32' >> Make.user
make win-extras
make dist
