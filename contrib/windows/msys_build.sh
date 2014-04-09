#!/bin/sh
# Script to compile Julia in MSYS assuming 7zip is installed and on the path,
# or Cygwin assuming make, curl, and mingw64-$ARCH-gcc-g++ are installed

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
  archsuffix=64
else
  bits=32
  archsuffix=86
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

# Download most recent Julia binary for dependencies
echo "" > get-deps.log
if ! [ -e julia-installer.exe ]; then
  f=julia-0.3.0-prerelease-win$bits.exe
  echo "Downloading $f"
  curl -kLOsS http://s3.amazonaws.com/julialang/bin/winnt/x$archsuffix/0.3/$f
  echo "Extracting $f"
  7z x -y $f >> get-deps.log
fi
for i in bin/*.dll \ #lib/julia/*.a include/julia/uv*.h include/julia/tree.h \
    Git/bin/msys-1.0.dll Git/bin/msys-perl5_8.dll Git/bin/perl.exe Git/bin/sh.exe; do
  7z e -y julia-installer.exe "\$_OUTDIR/$i" \
    -ousr\\`dirname $i | sed -e 's|/julia||' -e 's|/|\\\\|g'` >> get-deps.log
done
# Remove libjulia.dll if it was copied from downloaded binary
rm -f usr/bin/libjulia.dll
rm -f usr/bin/libjulia-debug.dll

mingw=http://sourceforge.net/projects/mingw
if [ -z "$USEMSVC" ]; then
  if [ -z "`which ${CROSS_COMPILE}gcc 2>/dev/null`" ]; then
    f=mingw-w$bits-bin-$ARCH-20140102.7z
    if ! [ -e $f ]; then
      echo "Downloading $f"
      curl -kLOsS http://www.mpclab.net/$f
    fi
    echo "Extracting $f"
    7z x -y $f >> get-deps.log
    export PATH=$PATH:$PWD/mingw$bits/bin
    # If there is a version of make.exe here, it is mingw32-make which won't work
    rm -f mingw$bits/bin/make.exe
  fi
  export AR=${CROSS_COMPILE}ar

  f=llvm-3.3-$ARCH-w64-mingw32-juliadeps.7z
  # The MinGW binary version of LLVM doesn't include libgtest or libgtest_main
  $AR cr usr/lib/libgtest.a
  $AR cr usr/lib/libgtest_main.a
else
  export CC="$PWD/deps/libuv/compile cl -nologo"
  export AR="$PWD/deps/libuv/ar-lib lib"
  export LD="$PWD/linkld link"
  echo "override CC = $CC" >> Make.user
  echo 'override CXX = $(CC)' >> Make.user
  echo "override AR = $AR" >> Make.user
  echo "override LD = $LD" >> Make.user

  f=llvm-3.3.1-$ARCH-msvc11-juliadeps.7z
fi

if ! [ -e $f ]; then
  echo "Downloading $f"
  curl -kLOsS http://www.mpclab.net/$f
fi
echo "Extracting $f"
7z x -y $f >> get-deps.log
echo 'LLVM_CONFIG = $(JULIAHOME)/usr/bin/llvm-config' >> Make.user

# If no Fortran compiler installed, override with name of C compiler
# (this only fixes the unnecessary invocation of FC in openlibm)
if [ -z "`which ${CROSS_COMPILE}gfortran 2>/dev/null`" ]; then
  echo 'override FC = $(CC)' >> Make.user
fi

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
    curl -kLOsS $mingw/files/MSYS/Base$f.lzma
  fi
  7z x -y `basename $f.lzma` >> get-deps.log
  tar -xf `basename $f`
done
if [ -z "`which make 2>/dev/null`" ]; then
  mv bin/make.exe /usr/bin
  # msysgit has an ancient version of touch that fails with `touch -c nonexistent`
  cp bin/touch.exe /usr/bin
fi
for i in cat chmod echo false printf sort touch true; do
  mv bin/$i.exe usr/Git/bin
done

f=mingw$bits-pcre-8.34-1.fc21.noarch
if ! [ -e $f.rpm ]; then
  echo "Downloading $f"
  curl -kLOsS ftp://rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/m/$f.rpm
fi
7z x -y $f.rpm >> get-deps.log
7z x -y $f.cpio >> get-deps.log
echo 'override PCRE_CONFIG = $(JULIAHOME)/usr/bin/pcre-config' >> Make.user
# Move downloaded bin, lib, and include files into build tree
mv usr/$ARCH-w64-mingw32/sys-root/mingw/bin/* usr/bin
mv usr/$ARCH-w64-mingw32/sys-root/mingw/lib/*.dll.a usr/lib
mv usr/$ARCH-w64-mingw32/sys-root/mingw/include/* usr/include
# Modify prefix in pcre-config
sed -i "s|prefix=/usr/$ARCH-w64-mingw32/sys-root/mingw|prefix=$PWD/usr|" usr/bin/pcre-config
chmod +x usr/bin/*

for lib in LLVM SUITESPARSE ARPACK BLAS LAPACK FFTW GMP MPFR \
    PCRE LIBUNWIND GRISU RMATH OPENSPECFUN; do
  echo "USE_SYSTEM_$lib = 1" >> Make.user
done
echo 'LIBBLAS = -L$(JULIAHOME)/usr/bin -lopenblas' >> Make.user
echo 'LIBBLASNAME = libopenblas' >> Make.user
echo 'override LIBLAPACK = $(LIBBLAS)' >> Make.user
echo 'override LIBLAPACKNAME = $(LIBBLASNAME)' >> Make.user
#echo 'override LIBUV = $(JULIAHOME)/usr/lib/libuv.a' >> Make.user
#echo 'override LIBUV_INC = $(JULIAHOME)/usr/include' >> Make.user

# Remaining dependencies:
# openlibm since we need it as a static library to work properly
# utf8proc since its headers are not in the binary download
echo 'override STAGE1_DEPS = uv random' >> Make.user
echo 'override STAGE2_DEPS = utf8proc' >> Make.user
echo 'override STAGE3_DEPS = ' >> Make.user
make -C deps get-openlibm get-utf8proc

# Disable git and enable verbose make in AppVeyor
if [ -n "$APPVEYOR" ]; then
  echo 'override NO_GIT = 1' >> Make.user
  #echo 'VERBOSE = 1' >> Make.user
fi

if [ -n "$USEMSVC" ]; then
  # Create a modified version of compile for wrapping link
  sed -e 's/-link//' -e 's/cl/link/g' -e 's/ -Fe/ -OUT:/' \
    -e 's|$dir/$lib|$dir/lib$lib|g' deps/libuv/compile > linkld
  chmod +x linkld

  # Openlibm doesn't build well with MSVC right now
  echo 'USE_SYSTEM_OPENLIBM = 1' >> Make.user
  # Since we don't have a static library for openlibm
  echo 'override UNTRUSTED_SYSTEM_LIBM = 0' >> Make.user

  # Compile libuv and utf8proc without -TP first, then add -TP
  make -C deps install-uv install-utf8proc
  cp usr/lib/uv.lib usr/lib/libuv.a
  echo 'override CC += -TP' >> Make.user
else
  echo 'override STAGE1_DEPS += openlibm' >> Make.user
fi

make
