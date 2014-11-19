#!/bin/sh
# build-time mini version of WinRPM, usage:
# ./winrpm.sh http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_13.1/ mingw64-hdf5
# depends on curl, xmllint, gunzip

set -e
url=$1
pkg=$2

retry_curl() {
  for i in $(seq 10); do
    curl -fLsS $1 && return
    #sleep 2
  done
  echo "failed to download $1"
  exit 1
}

# the local-name() complication here is due to xml namespaces
eval $(retry_curl $url/repodata/repomd.xml | xmllint --xpath \
  "/*[local-name()='repomd']/*[local-name()='data' and @type='primary'] \
  /*[local-name()='location']/@href" -)

case $href in
  *.gz)
    primary=$(retry_curl $url/$href | gunzip);;
  *)
    primary=$(retry_curl $url/$href);;
esac

rpm_requires() {
  for i in $(echo $primary | xmllint --xpath "//*[local-name()='package'] \
      /*[local-name()='name' and .='$1']/../*[local-name()='arch' and .='noarch']/.. \
      /*[local-name()='format']/*[local-name()='requires']/*[local-name()='entry']/@name" -); do
    eval $i
    echo $name
  done
}
rpm_requires $pkg
