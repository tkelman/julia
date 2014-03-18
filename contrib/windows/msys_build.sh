#!/bin/sh
# Script to compile Julia in MSYS assuming 7zip is installed and on the path,
# or Cygwin assuming make, wget, and mingw64-$ARCH-gcc-g++ are installed

# Run in top-level Julia directory
cd `dirname "$0"`/../..
# Stop on error
set -e

# If ARCH environment variable not set, choose based on uname -m
if [ -z "$ARCH" ]; then
  export ARCH=`uname -m`
fi
if [ $ARCH = x86_64 ]; then
  bits=64
  exc=seh
else
  bits=32
  exc=sjlj
fi
echo "override ARCH = $ARCH" > Make.user

# Set XC_HOST if in Cygwin
if [ -n "`uname | grep CYGWIN`" ]; then
  if [ -z "$XC_HOST" ]; then
    export XC_HOST="$ARCH-w64-mingw32"
  fi
  echo "override BUILD_MACHINE = $ARCH-pc-cygwin" >> Make.user
  CROSS_COMPILE="$XC_HOST-"
  # Set HOSTCC if we don't have Cygwin gcc installed
  if [ -z "`which gcc 2>/dev/null`" ]; then
    echo 'override HOSTCC = $(CROSS_COMPILE)gcc' >> Make.user
  fi
else
  CROSS_COMPILE=""
fi

echo "" > get-deps.log
mingw=http://sourceforge.net/projects/mingw
if [ -z "$USE_MSVC" ]; then
  if [ -z "`which ${CROSS_COMPILE}gcc 2>/dev/null`" ]; then
    echo "Downloading $ARCH-w64-mingw32 compilers"
    # TODO: find a smaller build with just gcc, g++?
    f=x$bits-4.8.1-release-win32-$exc-rev5.7z
    if ! [ -e $f ]; then
      deps/jldownload ${mingw}builds/files/host-windows/releases/4.8.1/$bits-bit/threads-win32/$exc/$f >> get-deps.log 2>&1
    fi
    echo "Extracting $ARCH-w64-mingw32 compilers"
    7z x -y $f >> get-deps.log
    export PATH=$PATH:$PWD/mingw$bits/bin
  fi
  export AR=${CROSS_COMPILE}ar
else
  # compile and ar-lib scripts to use MSVC instead of MinGW compiler
  deps/jldownload compile http://git.savannah.gnu.org/cgit/automake.git/plain/lib/compile?id=v1.14.1 >> get-deps.log 2>&1
  deps/jldownload ar-lib http://git.savannah.gnu.org/cgit/automake.git/plain/lib/ar-lib?id=v1.14.1 >> get-deps.log 2>&1
  chmod +x compile
  chmod +x ar-lib
  echo "override CC = $PWD/compile cl -TP" >> Make.user
  echo 'override CXX = $(CC)' >> Make.user
  echo 'override FC = $(CC)' >> Make.user
  export AR="$PWD/ar-lib lib"
  echo "override AR = $AR" >> Make.user
fi

# If no Fortran compiler installed, override with name of C compiler
# (this only fixes the unnecessary invocation of FC in openlibm)
if [ -z "`which ${CROSS_COMPILE}gfortran 2>/dev/null`" ]; then
  echo "override FC = ${CROSS_COMPILE}gcc" >> Make.user
fi

for f in juliadeps-$ARCH-w64-mingw32.7z llvm-3.3-$ARCH-w64-mingw32-juliadeps.7z; do
  if ! [ -e $f ]; then
    echo "Downloading $f"
    deps/jldownload http://sourceforge.net/projects/juliadeps-win/files/$f >> get-deps.log 2>&1
  fi
  echo "Extracting $f"
  7z x -y $f >> get-deps.log
done
echo 'LLVM_CONFIG = $(JULIAHOME)/usr/bin/llvm-config' >> Make.user
echo 'LLVM_LLC = $(JULIAHOME)/usr/bin/llc' >> Make.user
# The binary version of LLVM doesn't include libgtest or libgtest_main
$AR cr usr/lib/libgtest.a
$AR cr usr/lib/libgtest_main.a

if [ -z "`which make 2>/dev/null`" ]; then
  download="/make/make-3.81-2/make-3.81-2-msys-1.0.11-bin.tar"
  if [ -n "`uname | grep CYGWIN`" ]; then
    echo "Install the Cygwin package for 'make' and try again."
    exit 1
  fi
else
  download=""
fi
for f in $download \
    /coreutils/coreutils-5.97-2/coreutils-5.97-2-msys-1.0.11-bin.tar; do
  if ! [ -e `basename $f.lzma` ]; then
    echo "Downloading `basename $f`"
    deps/jldownload $mingw/files/MSYS/Base$f.lzma >> get-deps.log 2>&1
  fi
  7z x -y `basename $f.lzma` >> get-deps.log
  tar -xf `basename $f`
done
if [ -z "`which make 2>/dev/null`" ]; then
  mv bin/make.exe /usr/bin
fi
for i in cat chmod echo false printf sort touch true; do
  mv bin/$i.exe usr/Git/bin
done

for f in readline-6.2-3.fc20 termcap-1.3.1-16.fc20 pcre-8.34-1.fc21; do
  if ! [ -e mingw$bits-$f.noarch.rpm ]; then
    echo "Downloading $f"
    deps/jldownload ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/mingw$bits-$f.noarch.rpm >> get-deps.log 2>&1
  fi
  7z x -y mingw$bits-$f.noarch.rpm >> get-deps.log
  7z x -y mingw$bits-$f.noarch.cpio >> get-deps.log
done
echo 'override READLINE = -lreadline -lhistory' >> Make.user
echo 'override PCRE_CONFIG = $(JULIAHOME)/usr/bin/pcre-config' >> Make.user
# Move downloaded bin, lib, and include files into build tree
mv usr/$ARCH-w64-mingw32/sys-root/mingw/bin/* usr/bin
mv usr/$ARCH-w64-mingw32/sys-root/mingw/lib/*.dll.a usr/lib
if ! [ -d usr/include/readline ]; then
  mv usr/$ARCH-w64-mingw32/sys-root/mingw/include/* usr/include
fi
# Modify prefix in pcre-config
sed -i "s|prefix=/usr/$ARCH-w64-mingw32/sys-root/mingw|prefix=$PWD/usr|" usr/bin/pcre-config
chmod +x usr/bin/*

for lib in LLVM SUITESPARSE ARPACK BLAS LAPACK FFTW GMP MPFR \
    PCRE LIBUNWIND READLINE GRISU RMATH OPENSPECFUN LIBUV; do
  echo "USE_SYSTEM_$lib = 1" >> Make.user
done
echo 'LIBBLAS = -L$(JULIAHOME)/usr/bin -lopenblas' >> Make.user
echo 'LIBBLASNAME = libopenblas' >> Make.user
echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
echo 'override LIBUV = $(JULIAHOME)/usr/lib/libuv.a' >> Make.user
echo 'override LIBUV_INC = $(JULIAHOME)/usr/include' >> Make.user

# Remaining dependencies:
# openlibm (and readline?) since we need these as static libraries to
# work properly (not included as part of Julia Windows binaries yet)
# utf8proc since its headers are not in the binary download
echo 'override STAGE2_DEPS = utf8proc' >> Make.user
echo 'override STAGE3_DEPS = ' >> Make.user
echo 'Downloading openlibm, utf8proc sources'
make -C deps get-openlibm utf8proc-v1.1.6/Makefile >> get-deps.log 2>&1

if [ -n "$USE_MSVC" ]; then
  # Openlibm doesn't build well with MSVC right now
  echo 'USE_SYSTEM_OPENLIBM = 1' >> Make.user
  echo 'override STAGE1_DEPS = ' >> Make.user
  # Since we don't have a static library for openlibm
  echo 'override UNTRUSTED_SYSTEM_LIBM = 0' >> Make.user

  # Fix MSVC compilation issues
  sed -i 's/-Wall -Wno-strict-aliasing//' src/Makefile
  sed -i 's/-Wall -Wno-strict-aliasing//' src/support/Makefile
  sed -i 's!$(LLVM_CONFIG) --cxxflags!$(LLVM_CONFIG) --cxxflags | sed "s/-Woverloaded-virtual -Wcast-qual//"!g' src/Makefile
  sed -i "s/_setjmp.win$bits.o _longjmp.win$bits.o//g" src/support/Makefile # this probably breaks exception handling
  sed -i 's/char bool/char _bool/' deps/utf8proc-v1.1.6/utf8proc.h
  sed -i 's/false, true/_false, _true/' deps/utf8proc-v1.1.6/utf8proc.h
  sed -i 's/buffer = malloc/buffer = (int32_t *) malloc/' deps/utf8proc-v1.1.6/utf8proc.c
  sed -i 's/newptr = realloc/newptr = (int32_t *) realloc/' deps/utf8proc-v1.1.6/utf8proc.c
  #sed -i 's/-Wno-implicit-function-declaration//' deps/openlibm/Make.inc
else
  echo 'override STAGE1_DEPS = openlibm' >> Make.user
fi

# Disable git and enable verbose make in AppVeyor
if [ -n "$APPVEYOR" ]; then
 echo 'override NO_GIT = 1' >> Make.user
 echo 'VERBOSE = 1' >> Make.user
fi

make -j 4
#make -j 4 debug
# remove precompiled system image
rm usr/lib/julia/sys.dll
