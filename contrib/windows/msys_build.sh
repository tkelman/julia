#!/bin/sh
# Script to compile Julia in MSYS, assuming 7zip is installed and on the path,
# and dependency dll's have been copied into usr/bin (see appveyor.yml)

# Stop on error
set -e

for f in bin lib include Git/bin; do
  mkdir -p usr/$f
done

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

echo "" > get-deps.log
mingw=http://sourceforge.net/projects/mingw
if [ -z "$USE_MSVC" ]; then
  if [ -z "`which gcc 2>/dev/null`" ]; then
    echo "Downloading $ARCH-w64-mingw32 compilers"
    f=x$bits-4.8.1-release-win32-$exc-rev5.7z
    if ! [ -e $f ]; then
      # Screen output (including stderr 2>&1) from downloads is redirected
      # to a file to avoid filling up the AppVeyor log with progress bars.
      deps/jldownload ${mingw}builds/files/host-windows/releases/4.8.1/$bits-bit/threads-win32/$exc/$f >> get-deps.log 2>&1
    fi
    echo "Extracting $ARCH-w64-mingw32 compilers"
    7z x -y $f >> get-deps.log
    export PATH=$PATH:$PWD/mingw$bits/bin
  fi
  export AR=ar
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

for f in /make/make-3.81-3/make-3.81-3-msys-1.0.13-bin.tar \
         /gettext/gettext-0.18.1.1-1/libintl-0.18.1.1-1-msys-1.0.17-dll-8.tar \
         /libiconv/libiconv-1.14-1/libiconv-1.14-1-msys-1.0.17-dll-2.tar \
         /coreutils/coreutils-5.97-3/coreutils-5.97-3-msys-1.0.13-bin.tar; do
  echo "Downloading `basename $f`"
  if ! [ -e `basename $f.lzma` ]; then
    deps/jldownload $mingw/files/MSYS/Base$f.lzma >> get-deps.log 2>&1
  fi
  7z x -y `basename $f.lzma` >> get-deps.log
  tar -xf `basename $f`
done
if [ -z "`which make 2>/dev/null`" ]; then
  mv bin/make.exe /usr/bin
  cp bin/*.dll /usr/bin
fi
mv bin/*.dll usr/Git/bin
mv bin/cat.exe usr/Git/bin
mv bin/echo.exe usr/Git/bin
mv bin/printf.exe usr/Git/bin

echo 'Downloading LLVM binary'
f=llvm-3.3-w$bits-bin-$ARCH-20130804.7z
if ! [ -e $f ]; then
  deps/jldownload $mingw-w64-dgn/files/others/$f >> get-deps.log 2>&1
fi
echo 'Extracting LLVM binary'
7z x -y $f >> get-deps.log
mv llvm/bin/* usr/bin
mv llvm/lib/*.a usr/lib
if ! [ -d usr/include/llvm ]; then
  mv llvm/include/llvm usr/include
  mv llvm/include/llvm-c usr/include
fi
echo 'LLVM_CONFIG = $(JULIAHOME)/usr/bin/llvm-config' >> Make.user
echo 'LLVM_LLC = $(JULIAHOME)/usr/bin/llc' >> Make.user
# This binary version doesn't include libgtest or libgtest_main for some reason
$AR cr usr/lib/libgtest.a
$AR cr usr/lib/libgtest_main.a

echo 'Downloading readline, termcap, pcre binaries'
for f in readline-6.2-3.fc20 termcap-1.3.1-16.fc20 pcre-8.34-1.fc21; do
  if ! [ -e mingw$bits-$f.noarch.rpm ]; then
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

# Remove libjulia.dll if it was copied from downloaded binary
[ -e usr/bin/libjulia.dll ] && rm usr/bin/libjulia.dll
[ -e usr/bin/libjulia-debug.dll ] && rm usr/bin/libjulia-debug.dll

for lib in LLVM ZLIB SUITESPARSE ARPACK BLAS FFTW LAPACK GMP MPFR \
    PCRE LIBUNWIND READLINE GRISU RMATH OPENSPECFUN LIBUV OPENLIBM; do
  echo "USE_SYSTEM_$lib = 1" >> Make.user
done
echo 'LIBBLAS = -L$(JULIAHOME)/usr/bin -lopenblas' >> Make.user
echo 'LIBBLASNAME = libopenblas' >> Make.user
echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
echo 'override LIBUV = $(JULIAHOME)/usr/lib/libuv.a' >> Make.user
echo 'override LIBUV_INC = $(JULIAHOME)/usr/include' >> Make.user
# Since we don't have a static library for openlibm
echo 'override UNTRUSTED_SYSTEM_LIBM = 0' >> Make.user

# Remaining dependencies:
# openlibm (and readline?) since we need these as static libraries to
# work properly (not included as part of Julia Windows binaries yet)
# utf8proc since its headers are not in the binary download
echo 'override STAGE1_DEPS = ' >> Make.user
echo 'override STAGE2_DEPS = utf8proc' >> Make.user
echo 'override STAGE3_DEPS = ' >> Make.user
echo 'Downloading openlibm, utf8proc sources'
make -C deps get-openlibm utf8proc-v1.1.6/Makefile >> get-deps.log 2>&1

if [ -n "$USE_MSVC" ]; then
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
fi

# Disable git and enable verbose make in AppVeyor
if [ -n "$APPVEYOR" ]; then
 echo 'override NO_GIT = 1' >> Make.user
 echo 'VERBOSE = 1' >> Make.user
fi

make -j 4
make -j 4 debug
