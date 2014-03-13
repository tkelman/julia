#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming
# the following packages are installed:
# - make
# - wget
# - bsdtar
# - binutils (for `strings` in make install)
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-i686-gcc-g++ (for 32 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit, only if building openblas, arpack etc from source)
# - mingw64-i686-gcc-fortran (for 32 bit, only if building openblas, arpack etc from source)
# - python (only if building llvm from source)
# - gcc-g++ (only if building llvm from source)
# - diffutils (only if building llvm from source)
#
# This script is intended to be executed from the main julia directory
# as contrib/cygwin_build.sh. The only part that's absolutely necessary
# is setting XC_HOST, the rest of this script deals with using binaries
# for as many of Julia's dependencies as possible. This script assumes
# all dll's from the most recent binary download of Julia have been
# copied into usr/bin. Results will be more reliable but take longer
# if all dependencies are compiled from source as usual.

# Stop on error
set -e

# If XC_HOST environment variable not set, choose based on arch
if [ -z "$XC_HOST" ]; then
  if [ `arch` = x86_64 ]; then
    export XC_HOST=x86_64-w64-mingw32
  else
    export XC_HOST=i686-w64-mingw32
  fi
fi
export AR="$XC_HOST-ar"

echo "override BUILD_MACHINE = `arch`-pc-cygwin" > Make.user

# If no Fortran compiler installed, override with name of C compiler
# (this only fixes the unnecessary invocation of FC in openlibm)
if [ -z "`which $XC_HOST-gfortran 2>/dev/null`" ]; then
  echo 'override FC = $(XC_HOST)-gcc' >> Make.user
fi

echo 'Downloading LLVM binary'
if [ $XC_HOST = x86_64-w64-mingw32 ]; then
  f=llvm-3.3-w64-bin-x86_64-20130804.7z
  bits=64
else
  f=llvm-3.3-w32-bin-i686-20130804.7z
  bits=32
fi
if ! [ -e $f ]; then
  # Screen output (including stderr 2>&1) from downloads is redirected
  # to a file to avoid filling up the AppVeyor log with progress bars.
  deps/jldownload https://sourceforge.net/projects/mingw-w64-dgn/files/others/$f
fi
echo 'Extracting LLVM binary'
bsdtar -xf $f
if [ -d usr ]; then
  for f in bin lib include; do
    mkdir -p usr/$f
  done
  mv llvm/bin/* usr/bin
  mv llvm/lib/*.a usr/lib
  if ! [ -d usr/include/llvm ]; then
    mv llvm/include/llvm usr/include
    mv llvm/include/llvm-c usr/include
  fi
else
  mv llvm usr
fi
echo 'LLVM_CONFIG = $(JULIAHOME)/usr/bin/llvm-config' >> Make.user
echo 'LLVM_LLC = $(JULIAHOME)/usr/bin/llc' >> Make.user
# This binary version doesn't include libgtest or libgtest_main for some reason
$XC_HOST-ar cr usr/lib/libgtest.a
$XC_HOST-ar cr usr/lib/libgtest_main.a

echo 'Downloading UnxUtils for printf'
deps/jldownload http://sourceforge.net/projects/unxutils/files/unxutils/current/UnxUtils.zip >> get-deps.log 2>&1
bsdtar -xf UnxUtils.zip usr/local/wbin/printf.exe
mv usr/local/wbin/printf.exe usr/bin
chmod +x usr/bin/printf.exe
# Simple echo.exe with LF line endings instead of CRLF
$XC_HOST-gcc -o usr/bin/echo contrib/windows/echo.c

echo 'Downloading readline, libtermcap, pcre binaries'
for f in readline-6.2-3.fc20 termcap-1.3.1-16.fc20 pcre-8.34-1.fc21; do
  if ! [ -e mingw$bits-$f.noarch.rpm ]; then
    deps/jldownload ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw$bits-$f.noarch.rpm >> get-deps.log 2>&1
  fi
  bsdtar -xf mingw$bits-$f.noarch.rpm
done
echo 'override READLINE = -lreadline -lhistory' >> Make.user
echo 'override PCRE_CONFIG = $(JULIAHOME)/usr/bin/pcre-config' >> Make.user
# Move downloaded bin, lib, and include files into build tree
mv usr/$XC_HOST/sys-root/mingw/bin/* usr/bin
mv usr/$XC_HOST/sys-root/mingw/lib/*.dll.a usr/lib
if ! [ -d usr/include/readline ]; then
  mv usr/$XC_HOST/sys-root/mingw/include/* usr/include
fi
# Modify prefix in pcre-config
sed -i "s|prefix=/usr/$XC_HOST/sys-root/mingw|prefix=$PWD/usr|" usr/bin/pcre-config

# Remove libjulia.dll if it was copied from downloaded binary
[ -e usr/bin/libjulia.dll ] && rm usr/bin/libjulia.dll
[ -e usr/bin/libjulia-debug.dll ] && rm usr/bin/libjulia-debug.dll

for lib in LLVM ZLIB SUITESPARSE ARPACK BLAS FFTW LAPACK GMP MPFR \
    PCRE LIBUNWIND READLINE GRISU RMATH OPENSPECFUN LIBUV; do
  echo "USE_SYSTEM_$lib = 1" >> Make.user
done
echo 'LIBBLAS = -L$(JULIAHOME)/usr/bin -lopenblas' >> Make.user
echo 'LIBBLASNAME = libopenblas' >> Make.user
echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
# OpenBlas uses HOSTCC to compile getarch, but we might not have Cygwin GCC installed
if [ -z "`which gcc 2>/dev/null`" ]; then
  echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
fi
echo 'override LIBUV = $(JULIAHOME)/usr/lib/libuv.a' >> Make.user
echo 'override LIBUV_INC = $(JULIAHOME)/usr/include' >> Make.user

# Remaining dependencies:
# openlibm and readline since we need these as static libraries to work properly
# (not included as part of Julia Windows binaries yet)
# utf8proc since its headers are not in the binary download
echo 'override STAGE1_DEPS = openlibm' >> Make.user
echo 'override STAGE2_DEPS = utf8proc' >> Make.user
echo 'override STAGE3_DEPS = ' >> Make.user
echo 'Downloading openlibm, utf8proc sources'
make -C deps get-openlibm get-utf8proc >> get-deps.log 2>&1

# Disable git and enable verbose make in AppVeyor
if [ -n "$APPVEYOR" ]; then
 echo 'override NO_GIT = 1' >> Make.user
 echo 'VERBOSE = 1' >> Make.user
fi

make -j 4
make -j 4 debug
#make -C test file spawn
#make testall
