#!/bin/bash
set -x
set -e

RELEASE_URL="http://releases.nemomobile.org/snapshots/repos/platform/"
ARCHS="i486 i586 armv7l armv7hl"
USAGE='Usage: $0 --nemo-id <ID>'
API_URL="https://api.merproject.org/"

DATADIR="/srv/obs/build/"

DST_PRJ="nemo"

error () {
  echo "ERROR: $*"
  exit 1
}

parse_params () {
  while test $# -gt 0; do
    case $1 in
      *-nemo-id)
        nemoid="$2"
        shift
      ;;
      *)
        echo "Unknown parameter: $1"
        echo "$USAGE"
        exit 1
      ;;
    esac
    shift
  done
}

do_dod () {
    for arch in $ARCHS; do

      [[ $arch = armv7hl ]] && obsarch=armv8el
      [[ $arch = armv7l ]] && obsarch=armv7el
      [[ $arch = i586 ]] && obsarch=i586
      [[ $arch = i486 ]] && obsarch=i586

      # dereference mer level
      merid=$(curl -o - ${RELEASE_URL}/$nemoid/mer.id)

      project="$DST_PRJ:$nemoid:$arch"
      
      echo "Creating or refreshing $project $arch Download on Demand repos with merid '$merid'"

      osc -A ${API_URL} meta -F - prj $project <<EOF
<project name="$project">
  <title>Nemo $nemoid $narch Snapshot</title>
  <description>Nemo $nemoid $narch Snapshot</description>
  <person role="maintainer" userid="cibot"/>
  <person role="bugowner" userid="cibot"/>
  <publish>
    <disable/>
  </publish>
  <build>
    <disable/>
  </build>
  <download mtype="rpmmd" arch="$obsarch" baseurl="${RELEASE_URL}/$nemoid/$arch/" metafile="primary.xml"/>
  <repository name="$arch">
    <path project="mer:mds2:Core:$arch:$merid" repository="Core_$arch"/>
    <arch>$obsarch</arch>
  </repository>
</project>
EOF

      #FIXME: need better way to not race with repserver
      echo "Sleeping a moment while waiting repserver.."
      sleep 10
    
      primary=$(curl -nsk ${RELEASE_URL}/$nemoid/$arch/repodata/repomd.xml | grep location | grep primary | gawk -F'"' '{ print $2 }')
      mkdir -p $DATADIR/$project/$arch/$obsarch/:full
      rm -f $DATADIR/$project/$arch/$obsarch/:full/*.rpm
      curl -nsk ${RELEASE_URL}/$nemoid/$arch/$primary | gunzip > $DATADIR/$project/$arch/$obsarch/:full/primary.xml
      # NOTE: There might be more that needs to be handled than the schedulerstate file
      rm -f $DATADIR/$project/$arch/$obsarch/{:depends,:full.solv,:packstatus,:repodone,:repoinfo,:schedulerstate}
      chown -R obsrun:obsrun $DATADIR/$project
      /usr/sbin/obs_admin --rescan-repository $project $arch $obsarch
    done
}

nemoid=""
parse_params $@

if [ -z "$nemoid" ]; then
  error "$USAGE"
fi

do_dod

