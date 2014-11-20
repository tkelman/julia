#!/bin/sh
# build-time mini version of WinRPM, usage:
# ./winrpm.sh http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_13.1/ mingw64-hdf5
# depends on curl, xmllint, gunzip

set -e
url=$1
pkg=$2

retry_curl() {
  for i in $(seq 10); do
    # TODO: checksum verify downloads
    curl -fLsS $1 && return
    #sleep 2
  done
  echo "failed to download $1" >&2
  exit 1
}

xp="xmllint --xpath"
# the local-name() complication here is due to xml namespaces
loc="local-name()="
eval $(retry_curl $url/repodata/repomd.xml | $xp "/*[$loc'repomd'] \
  /*[$loc'data'][@type='primary']/*[$loc'location']/@href" -)

case $href in
  *.gz)
    primary=$(retry_curl $url/$href | gunzip);;
  *)
    primary=$(retry_curl $url/$href);;
esac

# outputs <package> xml string for newest version
# don't include arch=src packages, those will list build-time dependencies
rpm_select() {
  candidates="<c>$(echo $primary | $xp "//*[$loc'package'] \
    [./*[$loc'name' and .='$1']][./*[$loc'arch' and .='noarch']]" - |
    sed -e 's|<rpm:|<|g' -e 's|</rpm:|</|g')</c>"
  # remove rpm namespacing so output can be parsed by xmllint later
  epochs=""
  for i in $(echo $candidates | $xp "/c/package/version/@epoch" -); do
    eval $i
    if [ -z "$epochs" ]; then
      epochs=$epoch
    else
      epochs="$epochs\n$epoch"
    fi
  done
  maxepoch=$(echo -e $epochs | sort -V -u | tail -n 1)
  vers=""
  for i in $(echo $candidates | $xp "/c/package/version \
      [@epoch='$maxepoch']/@ver" -); do
    eval $i
    if [ -z "$vers" ]; then
      vers=$ver
    else
      vers="$vers\n$ver"
    fi
  done
  maxver=$(echo -e $vers | sort -V -u | tail -n 1)
  rels=""
  for i in $(echo $candidates | $xp "/c/package/version \
      [@epoch='$maxepoch'][@ver='$maxver']/@rel" -); do
    eval $i
    if [ -z "$rels" ]; then
      rels=$rel
    else
      rels="$rels\n$rel"
    fi
  done
  maxrel=$(echo -e $rels | sort -V -u | tail -n 1)
  repeats=$(echo -e $rels | sort -V | uniq -d | tail -n 1)
  if [ "$repeats" = "$maxrel" ]; then
    echo "warning: multiple candidates found for $1 with same version:" >&2
    echo "epoch $maxepoch, ver $maxver, rel $maxrel, picking at random" >&2
  fi
  echo $candidates | $xp "/c/package[version[@epoch='$maxepoch'] \
    [@ver='$maxver'][@rel='$maxrel']][1]" -
}
#for i in $pkg; do
#  echo "rpm_select $i:"
#  rpm_select $i
#done

# outputs package and dll names, e.g. mingw64(zlib1.dll)
rpm_requires() {
  for i in $(rpm_select $1 | $xp "/package/format/requires/entry/@name" -); do
    eval $i
    echo $name
  done
}
#for i in $pkg; do
#  echo "rpm_requires $i:"
#  rpm_requires $i
#done

# outputs package name, fails if multiple providers with different names
rpm_provides() {
  providers=$(echo $primary | $xp "//*[$loc'package'] \
    [./*[$loc'format']/*[$loc'provides']/*[$loc'entry'][@name='$1']] \
    /*[$loc'name']" - | sed -e 's|<name>||g' -e 's|</name>|\n|g' | sort -u)
  if [ $(echo $providers | wc -w) -gt 1 ]; then
    echo "found multiple providers $providers for $1" >&2
    echo "can't decide which to pick, bailing" >&2
    exit 1
  else
    echo $providers
  fi
}
#for i in $pkg; do
#  echo "rpm_provides $i:"
#  rpm_provides $i
#done

#toinstall=$pkg
#allrequires=""
#for i in $pkg; do
#  requires="$(rpm_requires $i)"
#  echo "requires of $i:"
#  echo $requires
#  allrequires="$allrequires $requires"
#  echo "all requires:"
#  echo $allrequires
#done
#echo "packages to install: $toinstall"
