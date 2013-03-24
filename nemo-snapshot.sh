#!/bin/bash

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

pushd $PREFIX/$PLATFORM
rm -f latest
ln -sf $RELEASE latest
popd

for arch in $ARCHS ; do
    pushd $PREFIX/$PLATFORM/$RELEASE/$arch
        rm -f *.repo
        createrepo .
    popd
    TEMP=$(mktemp -d)
    pushd $TEMP
        PATTERNS=`find $PREFIX/$PLATFORM/$RELEASE/$arch/ -name 'patterns*.noarch.rpm'`
        for pattern in $PATTERNS ; do
            rpm2cpio $pattern | cpio -uidv
        done
        COUNT=$(find . -type f -name "*.xml" | wc -l)
        echo "<patterns count=\"$COUNT\">" >  $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/patterns.xml
        find . -type f -name "*.xml" -exec cat {} + >> $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/patterns.xml
        echo "</patterns>" >>  $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/patterns.xml
        modifyrepo $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/patterns.xml $PREFIX/$PLATFORM/$RELEASE/$arch/repodata
    popd
    rm $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/patterns.xml
    rm -rf $TEMP

    # echo "Signing $arch repo with releases key ..."
    # $REPO_SIGN_COMMAND $PREFIX/$PLATFORM/$RELEASE/$arch/repodata/repomd.xml
done

# Check HW Adaptation repos.
ADAPTATIONS="ti:/omap3:/n900 ti:/omap3:/n9xx-common ti:/omap3:/n950-n9 ti:/omap4:/pandaboard x86:/x86-common"

for prj in $ADAPTATIONS ; do
    for arch in $ARCHS ; do
        if [ ! -d $SRCPREFIX/$levelsuffix/hw:/$prj/latest_$arch ]; then
            echo "Dir doesn't exist: $SRCPREFIX/$levelsuffix/hw:/$prj/latest_$arch"
            continue
        fi
        mkdir -p $PREFIX/hw/${prj//:/}/$RELEASE/$arch
        $RSYNC_COMMAND $EXCLUDES $SRCPREFIX/"$levelsuffix"/hw:/"$prj"/latest_$arch/* $PREFIX/hw/${prj//:/}/$RELEASE/$arch
        pushd $PREFIX/hw/${prj//:/}/$RELEASE/$arch
            rm -f *.repo
            createrepo .
        popd
        TEMP=$(mktemp -d)
        pushd $TEMP
            PATTERNS=`find $PREFIX/hw/${prj//:/}/$RELEASE/$arch/noarch/patterns*.noarch.rpm`
            for pattern in $PATTERNS ; do
                rpm2cpio $pattern | cpio -uidv
            done
            COUNT=$(find . -type f -name "*.xml" | wc -l)
            echo "<patterns count=\"$COUNT\">" >  $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata/patterns.xml
            find . -type f -name "*.xml" -exec cat {} + >> $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata/patterns.xml
            echo "</patterns>" >>  $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata/patterns.xml
            modifyrepo $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata/patterns.xml $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata
        popd
        rm $PREFIX/hw/${prj//:/}/$RELEASE/$arch/repodata/patterns.xml
        rm -r $TEMP
   done
   pushd $PREFIX/hw/${prj//:/}
   rm -f latest
   ln -sf $RELEASE latest
   popd
done



