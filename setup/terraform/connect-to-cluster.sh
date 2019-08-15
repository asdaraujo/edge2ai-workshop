#!/bin/bash
set -u
set -e
BASE_DIR=$(cd $(dirname $0); pwd -L)
CLUSTER_ID=$1

if [ ! -f .key.file.name -o ! -f .instance.list ]; then
  $BASE_DIR/list-details.sh > /dev/null
fi
PUBLIC_DNS=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $2}' .instance.list)
KEY_FILE=$BASE_DIR/$(cat $BASE_DIR/.key.file.name)

ssh -o StrictHostKeyChecking=no -i $KEY_FILE centos@$PUBLIC_DNS
