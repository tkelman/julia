#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming the following packages are installed:
# - dos2unix
# - make
# - wget
# - bsdtar
# - python (for llvm)
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit)
# - mingw-gcc-g++ (for 32 bit)
# - mingw-gcc-fortran (for 32 bit)
#
# This script is intended to be executed from the base julia directory as contrib/cygwin_build.sh

dos2unix contrib/relative_path.sh deps/jldownload deps/find_python_for_llvm 2>&1

if [ `arch` = x86_64 ]; then
  echo "XC_HOST = x86_64-w64-mingw32" > Make.user
  # download binary llvm
  wget https://sourceforge.net/projects/mingw-w64-dgn/files/others/llvm-3.3-w64-bin-x86_64-20130804.7z >> get-deps.log 2>&1
  bsdtar -xf llvm-3.3-w64-bin-x86_64-20130804.7z
  echo "USE_SYSTEM_LLVM = 1" >> Make.user
  echo "LLVM_CONFIG = $PWD/llvm/bin/llvm-config" >> Make.user
  echo "LLVM_LLC = $PWD/llvm/bin/llc" >> Make.user
else
  echo "XC_HOST = i686-pc-mingw32" > Make.user
  make -C deps get-llvm >> get-deps.log 2>&1
fi

#make -C deps getall >> get-deps.log 2>&1
make -C deps get-readline get-uv get-pcre get-double-conversion get-openlibm get-openspecfun \
  get-random get-openblas get-lapack get-fftw get-suitesparse get-arpack get-unwind \
  get-osxunwind get-gmp get-mpfr get-zlib get-patchelf get-utf8proc -j 4 >> get-deps.log 2>&1
dos2unix -f */*/configure */*/missing */*/config.sub */*/config.guess */*/depcomp 2>&1
make -j 4
