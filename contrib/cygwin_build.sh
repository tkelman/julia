#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming
# the following packages are installed:
# - make
# - wget
# - bsdtar
# - python (only if building llvm from source)
# - gcc (only if building llvm from source)
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit)
# - mingw-gcc-g++ (for 32 bit, not yet tested)
# - mingw-gcc-fortran (for 32 bit, not yet tested)
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

# Fix line endings in shell scripts used by Makefile
for f in contrib/relative_path.sh deps/jldownload deps/find_python_for_llvm base/version_git.sh; do
  tr -d '\r' < $f > $f.d2u
  mv $f.d2u $f
done

if [ `arch` = x86_64 ]; then
  echo 'XC_HOST = x86_64-w64-mingw32' > Make.user
  echo 'override BUILD_MACHINE = x86_64-pc-cygwin' >> Make.user
  
  # Download LLVM binary
  #f=llvm-3.3-w64-bin-x86_64-20130804.7z
  #if ! [ -e $f ]; then
    # Screen output (including stderr 2>&1) from downloads is redirected
    # to a file to avoid filling up the AppVeyor log with progress bars.
  #  deps/jldownload https://sourceforge.net/projects/mingw-w64-dgn/files/others/$f > get-deps.log 2>&1
  #fi
  #bsdtar -xf $f
  #if [ -d usr ]; then
    for f in bin lib include; do
      mkdir -p usr/$f
    done
  #  mv llvm/bin/* usr/bin
  #  mv llvm/lib/*.a usr/lib
  #  if ! [ -d usr/include/llvm ]; then
  #    mv llvm/include/llvm usr/include
  #    mv llvm/include/llvm-c usr/include
  #  fi
  #else
  #  mv llvm usr
  #fi
  #echo 'LLVM_CONFIG = $(JULIAHOME)/usr/bin/llvm-config' >> Make.user
  #echo 'LLVM_LLC = $(JULIAHOME)/usr/bin/llc' >> Make.user
  # This binary version doesn't include libgtest or libgtest_main for some reason
  #x86_64-w64-mingw32-ar cr usr/lib/libgtest.a
  #x86_64-w64-mingw32-ar cr usr/lib/libgtest_main.a
  
  # Download MinGW binaries from Fedora rpm's for readline,
  # libtermcap (dependency of readline), and pcre (for pcre-config)
  for f in readline-6.2-3.fc20 termcap-1.3.1-16.fc20 pcre-8.34-1.fc21; do
    if ! [ -e mingw64-$f.noarch.rpm ]; then
      deps/jldownload ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw64-$f.noarch.rpm >> get-deps.log 2>&1
    fi
    bsdtar -xf mingw64-$f.noarch.rpm
  done
  echo 'override READLINE = -lreadline -lhistory' >> Make.user
  echo 'override PCRE_CONFIG = $(JULIAHOME)/usr/bin/pcre-config' >> Make.user
  
  # Move all downloaded bin, lib, and include files into build tree
  mv usr/x86_64-w64-mingw32/sys-root/mingw/bin/* usr/bin
  mv usr/x86_64-w64-mingw32/sys-root/mingw/lib/*.dll.a usr/lib
  if ! [ -d usr/include/readline ]; then
    mv usr/x86_64-w64-mingw32/sys-root/mingw/include/* usr/include
  fi
  # Modify prefix in pcre-config
  sed -i "s|prefix=/usr/x86_64-w64-mingw32/sys-root/mingw|prefix=$PWD/usr|" usr/bin/pcre-config
else
  echo 'XC_HOST = i686-pc-mingw32' > Make.user
  echo 'override BUILD_MACHINE = i686-pc-cygwin' >> Make.user
  
  # TODO: 32 bit versions of LLVM, readline, pcre
fi

# Remove libjulia.dll if it was copied from downloaded binary
[ -e usr/bin/libjulia.dll ] && rm usr/bin/libjulia.dll
[ -e usr/bin/libjulia-debug.dll ] && rm usr/bin/libjulia-debug.dll

for lib in ZLIB SUITESPARSE ARPACK BLAS FFTW LAPACK GMP MPFR \
    PCRE LIBUNWIND READLINE GRISU OPENLIBM RMATH OPENSPECFUN; do
  echo "USE_SYSTEM_$lib = 1" >> Make.user
done
echo 'LIBBLAS = -L$(JULIAHOME)/usr/bin -lopenblas' >> Make.user
echo 'LIBBLASNAME = libopenblas' >> Make.user
echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
# OpenBlas uses HOSTCC to compile getarch, but we might not have Cygwin GCC installed
if [ -z `which gcc 2>/dev/null` ]; then
  echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
fi
# Set UNTRUSTED_SYSTEM_LIBM to 0 since we don't have an openlibm static library
# (may just need to build from source instead...)
echo 'override UNTRUSTED_SYSTEM_LIBM = 0' >> Make.user
#echo 'override LIBUV_INC = $(JULIAHOME)/usr/include' >> Make.user

# Only need to build libuv for now, until Windows binaries get updated with latest bump
echo 'override STAGE1_DEPS = uv llvm' >> Make.user
# Need utf8proc since its headers are not in the binary download
echo 'override STAGE2_DEPS = utf8proc' >> Make.user
echo 'override STAGE3_DEPS = ' >> Make.user

make -C deps get-llvm get-uv get-utf8proc

# Fix line endings in libuv's configure scripts
for f in configure missing config.sub config.guess depcomp; do
  tr -d '\r' < deps/libuv/$f > deps/libuv/$f.d2u
  mv deps/libuv/$f.d2u deps/libuv/$f
done

# Disable git and enable verbose make in AppVeyor
if [ -n "$APPVEYOR" ]; then
 echo 'override NO_GIT = 1' >> Make.user
 echo 'VERBOSE = 1' >> Make.user
fi

make -j 4 testall
