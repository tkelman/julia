#!/bin/bash

# Run in top-level Julia directory
cd `dirname "$0"`/../..
# Stop on error
set -e

git checkout -b $WERCKER_GIT_BRANCH $WERCKER_GIT_COMMIT
# update timestamps to prevent pcre from rebuilding every time
curl https://gist.githubusercontent.com/jeffery/1115504/raw/GitRepoUpdateTimestamp.sh | bash

# This is for compatibility with Windows XP
echo 'LLVM_FLAGS = ac_cv_have_decl_strerror_s=no' > Make.user

# check if cache is ready, if not build a few dependencies at a time
cache_ready=1
for XC_HOST in i686-w64-mingw32 x86_64-w64-mingw32; do
  export XC_HOST
  make distcleanall > /dev/null 2>&1
  rm -rf dist-extras
  mkdir -p $WERCKER_CACHE_DIR/$XC_HOST
  if ! [ -e $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar.gz ]; then
    make win-extras
    tar -czf $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar.gz dist-extras
  fi
  mkdir -p usr/bin
  if [ -e $WERCKER_CACHE_DIR/$XC_HOST/usr.tar.gz ]; then
    tar -xzf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar.gz
  fi
  for depgroup in "llvm fftw gmp mpfr pcre" "openblas suitesparse-wrapper arpack"; do
    if [ $cache_ready = 1 ]; then
      for i in $depgroup; do
        if [ -e $WERCKER_CACHE_DIR/$XC_HOST/$i.tar.gz ]; then
          tar -xzf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar.gz
        else
          cache_ready=0
        fi
        make -j8 -C deps install-$i
        if [ $i = suitesparse-wrapper ]; then
          tar -czf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar.gz deps/SuiteSparse-*/ deps/SuiteSparse-*.tar.gz
        else
          tar -czf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar.gz deps/$i-*/ deps/$i-*.tar.*
        fi
      done
    fi
  done
  tar -czf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar.gz usr
  unset XC_HOST
done

# do make dist, if all the dependencies are ready for both 32 and 64 bit
if [ $cache_ready = 1 ]; then
  for ARCH in i686 x86_64; do
    export XC_HOST=$ARCH-w64-mingw32
    make distcleanall > /dev/null 2>&1
    rm -rf dist-extras
    tar -xzf $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar.gz
    tar -xzf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar.gz
    for i in llvm fftw gmp mpfr pcre dsfmt openblas suitesparse arpack; do
      tar -xzf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar.gz
    done
    make -j8 dist
    curl -T julia-*.exe -utkelman:$BINTRAYKEY "https://api.bintray.com/content/tkelman/generic/Julia/0.4.0-dev/julia-0.4.0-dev-$WERCKER_GIT_COMMIT-$ARCH.exe;publish=1"
    mv julia-*.exe $WERCKER_OUTPUT_DIR
    unset XC_HOST
  done
fi
