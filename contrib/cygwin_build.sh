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

# The frequent use of 2>&1 is so AppVeyor doesn't highlight so many normal messages as errors
if [ -n "`file contrib/relative_path.sh | grep CRLF`" ]; then
  dos2unix contrib/relative_path.sh deps/jldownload deps/find_python_for_llvm 2>&1
fi

# Add -C (caching) to CONFIGURE_COMMON in deps/Makefile for slightly faster configure scripts
sed -i 's/CONFIGURE_COMMON = --prefix/CONFIGURE_COMMON = -C --prefix/' deps/Makefile

if [ `arch` = x86_64 ]; then
  echo "XC_HOST = x86_64-w64-mingw32" > Make.user
  echo "override BUILD_MACHINE = x86_64-pc-cygwin" >> Make.user

  # Download LLVM binary
  wget https://sourceforge.net/projects/mingw-w64-dgn/files/others/llvm-3.3-w64-bin-x86_64-20130804.7z > get-deps.log 2>&1
  bsdtar -xf llvm-3.3-w64-bin-x86_64-20130804.7z
  # Copy MinGW libs into llvm/bin folder
  cp /usr/x86_64-w64-mingw32/sys-root/mingw/bin/*.dll llvm/bin
  echo "USE_SYSTEM_LLVM = 1" >> Make.user
  echo "LLVM_CONFIG = $PWD/llvm/bin/llvm-config" >> Make.user
  echo "LLVM_LLC = $PWD/llvm/bin/llc" >> Make.user
  echo "LDFLAGS = -L$PWD/llvm/lib" >> Make.user
  
  # Download OpenBlas binary
  wget -O openblas.7z "https://drive.google.com/uc?export=download&id=0B4DmELLTwYmlVWxuTU1QOHozbWM" >> get-deps.log 2>&1
  bsdtar -xf openblas.7z
  echo "USE_SYSTEM_BLAS = 1" >> Make.user
  echo "LIBBLAS = -L$PWD/lib -lopenblas" >> Make.user
  echo "LIBBLASNAME = libopenblas" >> Make.user
else
  echo "XC_HOST = i686-pc-mingw32" > Make.user
  echo "override BUILD_MACHINE = i686-pc-cygwin" >> Make.user

  make -C deps get-llvm get-openblas > get-deps.log 2>&1
  # OpenBlas uses HOSTCC to compile getarch, but we might not have Cygwin GCC installed
  if [ -z `which gcc 2>/dev/null` ]; then
    echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
  fi
fi

#make -C deps getall >> get-deps.log 2>&1
make -C deps get-readline get-uv get-pcre get-double-conversion get-openlibm \
  get-openspecfun get-random get-lapack get-fftw get-suitesparse get-arpack get-unwind \
  get-osxunwind get-gmp get-mpfr get-zlib get-patchelf get-utf8proc >> get-deps.log 2>&1

if [ -n "`file deps/libuv/missing | grep CRLF`" ]; then
  dos2unix -f */*/configure */*/missing */*/config.sub */*/config.guess */*/depcomp 2>&1
fi

make -j 4
