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
  if ! [ -e $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar ]; then
    make win-extras
    tar -cf $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar dist-extras
  fi
  mkdir -p usr/bin
  if [ -e $WERCKER_CACHE_DIR/$XC_HOST/usr.tar ]; then
    tar -xf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar
  fi
  for depgroup in "llvm fftw gmp mpfr pcre dsfmt" "openblas suitesparse arpack"; do
    if [ $cache_ready = 1 ]; then
      for i in $depgroup; do
        if [ -e $WERCKER_CACHE_DIR/$XC_HOST/$i.tar ]; then
          tar -xf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar
        else
          cache_ready=0
        fi
        make -j8 -C deps install-$i
        if [ $i = suitesparse ]; then
          tar -cf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar deps/SuiteSparse-*/ deps/SuiteSparse-*.tar.gz
        else
          tar -cf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar deps/$i-*/ deps/$i-*.tar.*
        fi
      done
    fi
  done
  tar -cf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar usr
done

# do make dist, if all the dependencies are ready for both 32 and 64 bit
if [ $cache_ready = 1 ]; then
  for XC_HOST in i686-w64-mingw32 x86_64-w64-mingw32; do
    export XC_HOST
    make distcleanall > /dev/null 2>&1
    rm -rf dist-extras
    tar -xf $WERCKER_CACHE_DIR/$XC_HOST/dist-extras.tar
    tar -xf $WERCKER_CACHE_DIR/$XC_HOST/usr.tar
    for i in llvm fftw gmp mpfr pcre dsfmt openblas suitesparse arpack; do
      tar -xf $WERCKER_CACHE_DIR/$XC_HOST/$i.tar
    done
    make -j8 dist
    mv julia-*.exe $WERCKER_OUTPUT_DIR
  done
fi

# TODO: deploy to S3?
