#!/bin/bash

if [[ "$#" < 2 ]]; then
  echo "Usage: $0 <PROJECT> <REPOSITORY>"
  exit 1
fi

PROJECT=$1
REPOSITORY=$2
BUILD_ARCH_MAPPINGS=(
"armv7hl armv8el"
"armv7tnhl armv8el"
"i486 i586"
)

ARCH=$(echo $REPOSITORY| sed -e 's/^[a-z]*_//')

BUILD_ARCH=${ARCH}
for MAP in "${BUILD_ARCH_MAPPINGS[@]}"
do
    read arch b_arch <<< $MAP
    if [[ "$ARCH" == "$arch" ]]; then
        BUILD_ARCH=$b_arch
        break;
    fi
done

SED_PATTERN="/<result project=\"${PROJECT}\" repository=\"${REPOSITORY}\" arch=\"${BUILD_ARCH}\"/,/<\/result>/p"

output=$(curl -s https://api.merproject.org/public/build/${PROJECT}/_result | sed -ne "${SED_PATTERN}" | grep status)
not_succeeded=$(echo $output | sed -e 's/<status /\n/g' | sed -e 's/> <\/status>//g' | sed -e 's/\/>//g' | grep -v succeeded | grep -v excluded)
echo ""
if [[ $not_succeeded ]]; then
  echo "Found following errors from project '$PROJECT' with repository '$REPOSITORY' and build arch '$BUILD_ARCH'"
  echo "$not_succeeded"
else
  echo "No errors found from project '$PROJECT' with repository '$REPOSITORY' and build arch '$BUILD_ARCH'"
fi

