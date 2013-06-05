#!/bin/bash

# Copyright (C) 2013 Jolla Ltd.
# Contact: Marko Saukko <marko.saukko@jollamobile.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

RELEASE=""
PREFIX="/srv/obs/repos/releases.nemomobile.org/"

autorelease () {

  DATE=$(date "+0.%Y%m%d.0.")
  SEQ=1
  while [ -d $PREFIX/$PLATFORM/$DATE$SEQ ]; do
    SEQ=$((SEQ + 1))
  done
  RELEASE="$DATE$SEQ"

}

autorelease

RELEASE_DIR=$PREFIX/releases/$RELEASE
MER_RELEASE=

mkdir -p $RELEASE_DIR

echo "Release directory '$RELEASE_DIR'"
echo

# Go through all the different repos in nemo snapshots
for DIR in `find $PREFIX/snapshots/ -name 'latest'`; do
  # take only the part after snapshots to dir structure
  DIR_SUFFIX=$(echo $DIR | awk '{ split($0,a,"snapshots/"); print a[2]}')
  REPO_RELEASE=$(readlink $DIR)
  DIR_SUFFIX=${DIR_SUFFIX/latest/$REPO_RELEASE}

  # TODO: This assumes same mer release id for each repo
  if [ -z $MER_RELEASE ]; then
    MER_RELEASE=$(cat $DIR/mer.id)
  fi

  mkdir -p $RELEASE_DIR/${DIR_SUFFIX/$REPO_RELEASE//}
  echo "Copying ${DIR/latest/$REPO_RELEASE}/* to $RELEASE_DIR/${DIR_SUFFIX/$REPO_RELEASE//}"
  cp -al ${DIR/latest/$REPO_RELEASE}/* $RELEASE_DIR/${DIR_SUFFIX/$REPO_RELEASE//}

  # Store information about the nemo snapshot this data is originated from
  echo "Nemo snapshot id '$REPO_RELEASE' stored to $RELEASE_DIR/${DIR_SUFFIX/$REPO_RELEASE//}/nemo.id"
  echo "$REPO_RELEASE" > $RELEASE_DIR/${DIR_SUFFIX/$REPO_RELEASE//}/nemo.id
  echo
done

# Create a rewrite rule to mer release so that we don't need to copy that data to another infra
echo "Creating mer release link to release $MER_RELEASE to $RELEASE_DIR/repos/mer/.htaccess"
mkdir -p $RELEASE_DIR/repos/mer/
cat > $RELEASE_DIR/repos/mer/.htaccess << EOF
RewriteEngine on
RewriteRule (.*) http://releases.merproject.org/releases/$MER_RELEASE/\$1 [R,L]
EOF

# Remove the mer.id info that was in snapshot dirs
find $RELEASE_DIR/ -type f -name 'mer.id' -exec rm {} \;

# Store information about the mer release the link above links to
echo "Mer release id '$MER_RELEASE' stored to $RELEASE_DIR/repos/mer.id"
echo "$MER_RELEASE" > $RELEASE_DIR/repos/mer.id

# Finalize with creationg symbolic link to latest
rm -f $PREFIX/releases/latest
ln -sf $RELEASE $PREFIX/releases/latest

echo "Release created."

