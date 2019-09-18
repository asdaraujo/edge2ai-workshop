#!/bin/bash
set -u
set -e

if [ $# -lt 2 ]; then
  echo "Syntax: $0 <cluster_number> command"
  exit 1
fi

BASE_DIR=$(cd $(dirname $0); pwd -L)
LOG_DIR=$BASE_DIR/logs
LOG_FILE=$LOG_DIR/command.$(date +%s).log

CLUSTER_ID=$1

if [ ! -f .key.file.name -o ! -f .instance.list ]; then
  $BASE_DIR/list-details.sh > /dev/null
fi
PUBLIC_DNS=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $2}' .instance.list)
KEY_FILE=$BASE_DIR/$(cat $BASE_DIR/.key.file.name)

shift
cmd=("$@")
ssh -o StrictHostKeyChecking=no -i $KEY_FILE centos@$PUBLIC_DNS "${cmd[@]}" | tee $LOG_FILE
echo "Log file: $LOG_FILE"
