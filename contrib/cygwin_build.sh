#!/bin/sh
# Script to cross-compile Julia from Cygwin to MinGW assuming
# the following packages are installed:
# - dos2unix
# - make
# - wget
# - bsdtar
# - python (for llvm)
# - mingw64-x86_64-gcc-g++ (for 64 bit)
# - mingw64-x86_64-gcc-fortran (for 64 bit)
# - mingw-gcc-g++ (for 32 bit, not yet tested)
# - mingw-gcc-fortran (for 32 bit, not yet tested)
#
# This script is intended to be executed from the main julia directory
# as contrib/cygwin_build.sh. The only part that's absolutely necessary
# is setting XC_HOST, the rest of this script deals with using binary
# downloads for as many of Julia's dependencies as possible. Results
# will be more reliable but take longer if all dependencies are compiled
# from source as usual.

# Stop on error
set -e

# Screen output from all downloads is redirected to a log file to
# avoid filling up the AppVeyor logs with progress bars

# The frequent use of 2>&1 is so AppVeyor doesn't highlight
# so many normal messages as errors
if [ -n "`file contrib/relative_path.sh | grep CRLF`" ]; then
  dos2unix contrib/relative_path.sh deps/jldownload \
    deps/find_python_for_llvm base/version_git.sh 2>&1
fi

# Add -C (caching) to CONFIGURE_COMMON in deps/Makefile for
# slightly faster configure scripts
sed -i 's/CONFIGURE_COMMON = --prefix/CONFIGURE_COMMON = -C --prefix/' deps/Makefile

if [ `arch` = x86_64 ]; then
  echo "XC_HOST = x86_64-w64-mingw32" > Make.user
  echo "override BUILD_MACHINE = x86_64-pc-cygwin" >> Make.user
  
  # Download LLVM binary
  f=llvm-3.3-w64-bin-x86_64-20130804.7z
  if ! [ -e $f ]; then
    wget https://sourceforge.net/projects/mingw-w64-dgn/files/others/$f > get-deps.log 2>&1
  fi
  bsdtar -xf $f
  if [ -d usr ]; then
    for i in bin lib include; do
      mkdir -p usr/$i
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
  echo "USE_SYSTEM_LLVM = 1" >> Make.user
  echo "LLVM_CONFIG = $PWD/usr/bin/llvm-config" >> Make.user
  echo "LLVM_LLC = $PWD/usr/bin/llc" >> Make.user
  # This binary version doesn't include libgtest or libgtest_main for some reason
  x86_64-w64-mingw32-ar cr usr/lib/libgtest.a
  x86_64-w64-mingw32-ar cr usr/lib/libgtest_main.a
  
  for lib in LLVM ZLIB SUITESPARSE ARPACK BLAS FFTW LAPACK GMP MPFR PCRE LIBUNWIND READLINE GRISU OPENLIBM RMATH OPENSPECFUN LIBUV; do
    echo "USE_SYSTEM_$lib = 1" >> Make.user
  done
  echo "LIBBLAS = -L$PWD/usr/bin -lopenblas" >> Make.user
  echo "LIBBLASNAME = libopenblas" >> Make.user
  echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
  echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
  #echo "USE_BLAS64 = 0" >> Make.user
  
  # Download MinGW binaries from Fedora rpm's for readline,
  # libtermcap (dependency of readline), and pcre (for pcre-config)
  for f in readline-6.2-3.fc20 termcap-1.3.1-16.fc20 pcre-8.34-1.fc21; do
    if ! [ -e mingw64-$f.noarch.rpm ]; then
      wget ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw64-$f.noarch.rpm >> get-deps.log 2>&1
    fi
    bsdtar -xf mingw64-$f.noarch.rpm
  done
  echo "override READLINE = -lreadline -lhistory" >> Make.user
  echo "override PCRE_CONFIG = $PWD/usr/bin/pcre-config" >> Make.user
  
  # Move all downloaded bin, lib, and include files into build tree
  mv usr/x86_64-w64-mingw32/sys-root/mingw/bin/* usr/bin
  mv usr/x86_64-w64-mingw32/sys-root/mingw/lib/*.dll.a usr/lib
  if ! [ -d usr/include/readline ]; then
    mv usr/x86_64-w64-mingw32/sys-root/mingw/include/* usr/include
  fi

  # Modify prefix in pcre-config
  sed -i "s|prefix=/usr/x86_64-w64-mingw32/sys-root/mingw|prefix=$PWD/usr|" usr/bin/pcre-config
  
  # skip all of the dependencies!
  echo "override STAGE1_DEPS = " >> Make.user
  echo "override STAGE2_DEPS = " >> Make.user
  echo "override STAGE3_DEPS = " >> Make.user
else
  echo "XC_HOST = i686-pc-mingw32" > Make.user
  echo "override BUILD_MACHINE = i686-pc-cygwin" >> Make.user
  
  make -C deps getall > get-deps.log 2>&1
fi
# OpenBlas uses HOSTCC to compile getarch, but we might not have Cygwin GCC installed
if [ -z `which gcc 2>/dev/null` ]; then
  echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
fi

# remove libjulia.dll if it was copied from downloaded binary
[ -e usr/bin/libjulia.dll ] && rm usr/bin/libjulia.dll
[ -e usr/bin/libjulia-debug.dll ] && rm usr/bin/libjulia-debug.dll
ls usr/bin

# modify deps/utf8proc_Makefile.patch to silence warning on library creation
#sed -i 's/$(AR) rs/$(AR) crs/' deps/utf8proc_Makefile.patch

#make -C deps get-utf8proc >> get-deps.log 2>&1
make -j 4
make testall
