#!/bin/sh
# build-time mini version of WinRPM, usage:
# ./winrpm.sh http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_13.1/ mingw64-hdf5
# depends on curl, xmllint, gunzip

set -e
url=$1
toinstall=$2

# there is a curl --retry flag but it wasn't working here for some reason
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

mkdir -p repodata
case $href in
  *.gz)
    retry_curl $url/$href | gunzip > $href;;
  *)
    retry_curl $url/$href > $href;;
esac

# outputs <package> xml string for newest version
# don't include arch=src packages, those will list build-time dependencies
rpm_select() {
  candidates="<c>$($xp "//*[$loc'package'][./*[$loc'name' and .='$1']] \
    [./*[$loc'arch' and .='noarch']]" $href 2>/dev/null | \
    sed -e 's|<rpm:|<|g' -e 's|</rpm:|</|g')</c>"
  # remove rpm namespacing so output can be parsed by xmllint later
  if [ "$candidates" = "<c></c>" ]; then
    echo "error: no package candidates found for $1" >&2
    rm $href
    exit 1
  fi
  epochs=""
  for i in $(echo $candidates | $xp "/c/package/version/@epoch" -); do
    eval $i
    epochs="$epochs $epoch"
  done
  maxepoch=$(echo $epochs | sed 's/ /\n/g' | sort -V -u | tail -n 1)
  vers=""
  for i in $(echo $candidates | $xp "/c/package/version \
      [@epoch='$maxepoch']/@ver" -); do
    eval $i
    vers="$vers $ver"
  done
  maxver=$(echo $vers | sed 's/ /\n/g' | sort -V -u | tail -n 1)
  rels=""
  for i in $(echo $candidates | $xp "/c/package/version \
      [@epoch='$maxepoch'][@ver='$maxver']/@rel" -); do
    eval $i
    rels="$rels $rel"
  done
  maxrel=$(echo $rels | sed 's/ /\n/g' | sort -V -u | tail -n 1)
  repeats=$(echo $rels | sed 's/ /\n/g' | sort -V | uniq -d | tail -n 1)
  if [ "$repeats" = "$maxrel" ]; then
    echo "warning: multiple candidates found for $1 with same version:" >&2
    echo "epoch $maxepoch, ver $maxver, rel $maxrel, picking at random" >&2
  fi
  echo $candidates | $xp "/c/package[version[@epoch='$maxepoch'] \
    [@ver='$maxver'][@rel='$maxrel']][1]" -
}
for i in $toinstall; do
  # fail if no available candidates for requested packages
  if [ -z "$(rpm_select $i)" ]; then
    exit 1
  fi
done

# outputs package and dll names, e.g. mingw64(zlib1.dll)
rpm_requires() {
  for i in $(rpm_select $1 | \
      $xp "/package/format/requires/entry/@name" - 2>/dev/null); do
    eval $i
    echo $name
  done
}

# outputs package name, fails if multiple providers with different names
rpm_provides() {
  providers=$($xp "//*[$loc'package'][./*[$loc'format']/*[$loc'provides'] \
    /*[$loc'entry'][@name='$1']]/*[$loc'name']" $href | \
    sed -e 's|<name>||g' -e 's|</name>|\n|g' | sort -u)
  if [ $(echo $providers | wc -w) -gt 1 ]; then
    echo "found multiple providers $providers for $1" >&2
    echo "can't decide which to pick, bailing" >&2
    rm $href
    exit 1
  else
    echo $providers
  fi
}

newpkgs=$toinstall
allrequires=""
while [ -n "$newpkgs" ]; do
  newrequires=""
  for i in $newpkgs; do
    for j in $(rpm_requires $i); do
      # leading and trailing spaces to ensure word match
      case " $allrequires $newrequires " in
        *" $j "*) # already on list
          ;;
        *)
          newrequires="$newrequires $j";;
      esac
    done
  done
  allrequires="$allrequires $newrequires"
  newpkgs=""
  for i in $newrequires; do
    provides="$(rpm_provides $i)"
    case " $toinstall $newpkgs " in
      *" $provides "*) # already on list
        ;;
      *)
        newpkgs="$newpkgs $provides";;
    esac
  done
  toinstall="$toinstall $newpkgs"
done
echo "packages to install: $toinstall"

rm $href
