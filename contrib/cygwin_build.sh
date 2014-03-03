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
# This script is intended to be executed from the main julia directory as contrib/cygwin_build.sh

# Stop on error
set -e

# Screen output from all downloads is redirected to a log file to avoid
# filling up the AppVeyor logs with progress bars

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
  if [ -d usr ]; then
    for i in bin lib; do
      mkdir -p usr/$i
      mv llvm/$i/* usr/$i
    done
    if ! [ -d usr/include/llvm ]; then
      mkdir -p usr/include
      mv llvm/include/llvm usr/include
      mv llvm/include/llvm-c usr/include
    fi
  else
    mv llvm usr
  fi
  echo "USE_SYSTEM_LLVM = 1" >> Make.user
  echo "LLVM_CONFIG = $PWD/usr/bin/llvm-config" >> Make.user
  echo "LLVM_LLC = $PWD/usr/bin/llc" >> Make.user
  # This binary version doesn't include libgtest or libgtest_main for some reason
  x86_64-w64-mingw32-ar cr usr/lib/libgtest.a
  x86_64-w64-mingw32-ar cr usr/lib/libgtest_main.a
  
  # Download OpenBlas binary
  wget -O openblas.7z "https://drive.google.com/uc?export=download&id=0B4DmELLTwYmlVWxuTU1QOHozbWM" >> get-deps.log 2>&1
  bsdtar -xf openblas.7z
  mv lib/libopenblas.dll usr/bin
  # Also needs msvcr90.dll?
  #cp /cygdrive/c/Windows/System32/drivers/msvcr90.dll usr/bin
  echo "USE_SYSTEM_BLAS = 1" >> Make.user
  echo "USE_SYSTEM_LAPACK = 1" >> Make.user
  echo "LIBBLAS = -L$PWD/usr/bin -lopenblas" >> Make.user
  echo "LIBBLASNAME = libopenblas" >> Make.user
  echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
  echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
  
  # Download readline binary
  wget ftp://rpmfind.net/linux/fedora/linux/releases/20/Everything/x86_64/os/Packages/m/mingw64-readline-6.2-3.fc20.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-readline-6.2-3.fc20.noarch.rpm
  echo "USE_SYSTEM_READLINE = 1" >> Make.user
  echo "override READLINE = -lreadline -lhistory" >> Make.user
  # Download libtermcap binary (dependency of readline)
  wget ftp://rpmfind.net/linux/fedora/linux/releases/20/Everything/x86_64/os/Packages/m/mingw64-termcap-1.3.1-16.fc20.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-termcap-1.3.1-16.fc20.noarch.rpm
  
  # Download pcre binary
  wget ftp://rpmfind.net/linux/fedora/linux/releases/18/Everything/x86_64/os/Packages/m/mingw64-pcre-8.31-1.fc18.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-pcre-8.31-1.fc18.noarch.rpm
  echo "USE_SYSTEM_PCRE = 1" >> Make.user
  
  # Download fftw binary
  wget ftp://rpmfind.net/linux/fedora/linux/releases/20/Everything/x86_64/os/Packages/m/mingw64-fftw-3.3.3-2.fc20.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-fftw-3.3.3-2.fc20.noarch.rpm
  echo "USE_SYSTEM_FFTW = 1" >> Make.user
  
  # Download gmp binary
  wget ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw64-gmp-5.1.3-1.fc21.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-gmp-5.1.3-1.fc21.noarch.rpm
  echo "USE_SYSTEM_GMP = 1" >> Make.user
  
  # Download mpfr binary
  wget ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw64-mpfr-3.1.2-1.fc21.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-mpfr-3.1.2-1.fc21.noarch.rpm
  echo "USE_SYSTEM_MPFR = 1" >> Make.user
  
  # Download zlib binary
  wget ftp://rpmfind.net/linux/fedora/linux/releases/20/Everything/x86_64/os/Packages/m/mingw64-zlib-1.2.8-2.fc20.noarch.rpm >> get-deps.log 2>&1
  bsdtar -xf mingw64-zlib-1.2.8-2.fc20.noarch.rpm
  echo "USE_SYSTEM_ZLIB = 1" >> Make.user
  
  # Move all downloaded bin, lib, and include files into build tree
  mv usr/x86_64-w64-mingw32/sys-root/mingw/bin/* usr/bin
  mv usr/x86_64-w64-mingw32/sys-root/mingw/lib/*.dll.a usr/lib
  if ! [ -d usr/include/readline ]; then
    mv usr/x86_64-w64-mingw32/sys-root/mingw/include/* usr/include
  fi
  
  # Rename versioned dll's
  mv usr/bin/libpcre-1.dll usr/bin/libpcre.dll
  mv usr/bin/libmpfr-4.dll usr/bin/libmpfr.dll
  cp usr/bin/libgmp-10.dll usr/bin/libgmp.dll
  mv usr/bin/libfftw3-3.dll usr/bin/libfftw3.dll
else
  echo "XC_HOST = i686-pc-mingw32" > Make.user
  echo "override BUILD_MACHINE = i686-pc-cygwin" >> Make.user
  
  make -C deps get-llvm get-openblas get-lapack get-readline get-pcre \
    get-fftw get-gmp get-mpfr get-zlib > get-deps.log 2>&1
fi
# OpenBlas uses HOSTCC to compile getarch, but we might not have Cygwin GCC installed
if [ -z `which gcc 2>/dev/null` ]; then
  echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
fi

#make -C deps getall >> get-deps.log 2>&1
make -C deps get-uv get-double-conversion get-openlibm get-openspecfun get-random \
  get-suitesparse get-arpack get-unwind get-osxunwind get-patchelf get-utf8proc >> get-deps.log 2>&1

if [ -n "`file deps/libuv/missing | grep CRLF`" ]; then
  dos2unix -f */*/configure */*/missing */*/config.sub */*/config.guess */*/depcomp 2>&1
fi

# Fix -fPIC warnings from SuiteSparse
make -C deps SuiteSparse-4.2.1/Makefile
sed -i 's/-fPIC//g' deps/SuiteSparse-4.2.1/SuiteSparse_config/SuiteSparse_config.mk
# Quiet down SuiteSparse's library creation
export ARFLAGS=cr

make -j 4
make testall
