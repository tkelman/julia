#!/bin/sh
# build-time version of WinRPM, usage:
# ./winrpm.sh http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_13.1/ mingw64-hdf5

set -e
url=$1
pkg=$2

eval `curl -fsS $url/repodata/repomd.xml | xmllint --xpath \
  "/*[local-name()='repomd']/*[local-name()='data' and @type='primary'] \
  /*[local-name()='location']/@href" -`
echo $href
