#!/bin/bash

trap ctrl_c INT

function ctrl_c() {
  echo "User interrupted the script with ctrl+c"
  exit 1
}

LEVEL=$1

[[ x$LEVEL = x ]] && echo "need level" && exit 1

umask "u=rwx,g=rwx,o=rx"

PREFIX="/data/obs/repos/releases.nemomobile.org/snapshots/repos/"
SRCPREFIX="/srv/obs/repos/repo.merproject.org/obs/nemo:/"
RSYNC_PASSWORD=
RSYNC_COMMAND="rsync --progress -m -rltOHxd"
#SIGNUSER=""
#PASSPHRASEFILE="/root/.phrases/$SIGNUSER"
#REPO_SIGN_COMMAND="gpg2 --batch --no-tty --local-user $SIGNUSER --passphrase-file $PASSPHRASEFILE --detach-sign --armor"
#RPM_SIGN_COMMAND="rpm --resign -D \"_gpg_name $SIGNUSER\""
ARCHS="i486 i586 x86_64 armv6l armv7l armv7hl armv7tnhl"
RELEASE=""

function expect_script
{
cat <<EOF
gets [open "$PASSPHRASEFILE" r] line
spawn $RPM_SIGN_COMMAND $RPMFILE
expect -exact "Enter pass phrase: "
send \$line\r
expect eof
exit
EOF
}

function sign_rpm
{
expect_script | /usr/bin/expect -f - >/dev/null
}

autorelease () {

  DATE=$(date "+0.%Y%m%d.0.")
  SEQ=1
  while [ -d $PREFIX/$PLATFORM/$DATE$SEQ ]; do
    SEQ=$((SEQ + 1))
  done
  RELEASE="$DATE$SEQ"

}

function update_repo_meta {
    REPO_DIR=$1
    # Drop OBS .repo files and create repository metadata
    pushd $REPO_DIR
        find . -type f -name "*.repo" -exec rm {} \;
        createrepo .
    popd
    # Extract the patterns from rpm's
    TEMP=$(mktemp -d)
    pushd $TEMP
        PATTERNS=`find $REPO_DIR/ -name 'patterns*.noarch.rpm'`
        for pattern in $PATTERNS ; do
            rpm2cpio $pattern | cpio -uidv
        done
        COUNT=$(find . -type f -name "*.xml" | wc -l)
        echo "<patterns count=\"$COUNT\">" >  $REPO_DIR/repodata/patterns.xml
        find . -type f -name "*.xml" -exec cat {} + >> $REPO_DIR/repodata/patterns.xml
        echo "</patterns>" >>  $REPO_DIR/repodata/patterns.xml
        modifyrepo $REPO_DIR/repodata/patterns.xml $REPO_DIR/repodata
    popd
    rm $REPO_DIR/repodata/patterns.xml
    rm -rf $TEMP
}

# Mer release is the same for everything as everything builds against same target 
# Each of our repos have armv7hl build so it is safe to assume that it is found.
MER_RELEASE=$(wget -qO- https://api.merproject.org/public/source/mer:$LEVEL/_meta | sed -ne '/<repository name="latest_armv7hl">/,/repository=/p' | grep path | awk '{ split($2,a,"\""); split(a[2],b,":"); print b[5] }')

if [[ $LEVEL = "devel" ]]; then
    levelsuffix="devel:/"
elif [[ $LEVEL = "testing" ]]; then
    levelsuffix="testing:/"
elif [[ $LEVEL = "stable" ]]; then
    levelsuffix="stable:/"
else
    echo "level should be devel, testing or stable"
    exit 1
fi

PLATFORM="platform"
autorelease
PRJS="mw ux apps"
EXCLUDES="--exclude /repocache/ --exclude /repodata/"

# Get the data from the repository OBS has published
for prj in $PRJS ; do
    for arch in $ARCHS ; do
        if [ ! -d "$SRCPREFIX/$levelsuffix/$prj/latest_$arch" ]; then
            echo "Dir doesn't exist: $SRCPREFIX/$levelsuffix/$prj/latest_$arch"
            continue
        fi
        mkdir -p $PREFIX/$PLATFORM/$RELEASE/$arch/$prj/
        $RSYNC_COMMAND $EXCLUDES $SRCPREFIX/$levelsuffix/$prj/latest_$arch/* $PREFIX/$PLATFORM/$RELEASE/$arch/$prj/
    done
done

#echo "Signing rpms with releases key ..."
#find $PREFIX/$PLATFORM/$RELEASE -type f -name "*.rpm" | while read RPMFILE ; do sign_rpm ; done

echo "This snapshot was made from $LEVEL projects $PRJS" > $PREFIX/$PLATFORM/$RELEASE/README

# Make this the new release
pushd $PREFIX/$PLATFORM
rm -f latest
ln -sf $RELEASE latest
popd

for arch in $ARCHS ; do
    update_repo_meta $PREFIX/$PLATFORM/$RELEASE/$arch/

    # Mark the mer id this repo was build against
    echo $MER_RELEASE > $PREFIX/$PLATFORM/$RELEASE/mer.id

    # echo "Signing $arch repo with releases key ..."
    # $REPO_SIGN_COMMAND $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/repomd.xml
done

# Check HW Adaptation repos.
ADAPTATIONS="ti:/omap3:/n900 ti:/omap3:/n9xx-common ti:/omap3:/n950-n9 ti:/omap4:/pandaboard x86:/x86-common"
ADAPTATIONS="ti:/omap3:/n9xx-common"

for prj in $ADAPTATIONS ; do
    for arch in $ARCHS ; do
        if [ ! -d $SRCPREFIX/$levelsuffix/hw:/$prj/latest_$arch ]; then
            echo "Dir doesn't exist: $SRCPREFIX/$levelsuffix/hw:/$prj/latest_$arch"
            continue
        fi
        mkdir -p $PREFIX/hw/${prj//:/}/$RELEASE/$arch
        $RSYNC_COMMAND $EXCLUDES $SRCPREFIX/"$levelsuffix"/hw:/"$prj"/latest_$arch/* $PREFIX/hw/${prj//:/}/$RELEASE/$arch        

        update_repo_meta $PREFIX/hw/${prj//:/}/$RELEASE/$arch/
   done

   # Mark the mer id this was build against
   echo $MER_RELEASE > $PREFIX/hw/${prj//:/}/$RELEASE/mer.id
   
   pushd $PREFIX/hw/${prj//:/}
   rm -f latest
   ln -sf $RELEASE latest
   popd
done

