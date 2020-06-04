#! /bin/bash

set -e
set -u

NOPROMPT=${1:-}

BASE_DIR=$(cd $(dirname $0); pwd -P)
KEY_FILE=$BASE_DIR/myRSAkey

if [ -e $BASE_DIR/stack.$NAMESPACE.sh ]; then
  source $BASE_DIR/stack.${NAMESPACE}.sh
elif [ -e $BASE_DIR/stack.sh ]; then
  source $BASE_DIR/stack.sh
elif [ -e $BASE_DIR/env.sh ]; then
  echo 'ERROR: The legacy "env.sh" file is now called "stack.sh".'
  echo '       Please rename "'"$BASE_DIR/env.sh"'" as "'"$BASE_DIR/stack.sh"'" and run this again.'
  exit 1
else
  echo 'ERROR: cannot find neither "'"$BASE_DIR/stack.sh"'" nor "'"$BASE_DIR/stack.${NAMESPACE}.sh"'".'
  exit 1
fi

#if [[ "${CDH_VERSION}" != *"6."* && "${CDH_VERSION}" != *"7.0."* && "${CDH_VERSION}" != *"7.1.0"* ]]; then
#  exit 0
#fi
#
## Check for required additional parcels
#missing_file=0
#for parcel in SCHEMAREGISTRY STREAMS_MESSAGING_MANAGER; do
#  if [ "$CSP_PARCEL_REPO" == "" ]; then
#    if [ $(find $BASE_DIR/parcels/ -name "${parcel}-*.parcel" | wc -l) == 0 ]; then
#      echo "WARNING: CSP_PARCEL_REPO is not set and there is no ${parcel}*.parcel file in $BASE_DIR/parcels" >&2
#      missing_file=1
#    fi
#    if [ $(find $BASE_DIR/parcels/ -name "${parcel}-*.parcel.sha" | wc -l) == 0 ]; then
#      echo "WARNING: CSP_PARCEL_REPO is not set and there is no ${parcel}*.parcel.sha file in $BASE_DIR/parcels" >&2
#      missing_file=1
#    fi
#  fi
#  if [ "$(eval "echo \$${parcel}_CSD_URL")" == "" -a $(find $BASE_DIR/csds/ -name "${parcel}-*.jar" | wc -l) == 0 ]; then
#    echo "WARNING: ${parcel}_CSD_URL is not set and there is no ${parcel}*.jar file in $BASE_DIR/csd" >&2
#    missing_file=1
#  fi
#done
#if [ "$NOPROMPT" == "" -a "$missing_file" == "1" ]; then
#  echo -e "\nSCHEMAREGISTRY and/or STREAMS_MESSAGING_MANAGER files/url are missing." >&2
#  echo -n "Do you want to continue without installing these components? (y|N) " >&2
#  read CONFIRM
#  if [ "$(echo "$CONFIRM" | tr "y" "Y")" != "Y" ]; then
#    echo "Aborting" >&2
#    exit 1
#  fi
#fi
#if [ "$missing_file" == "0" ]; then
#  echo OK
#fi
