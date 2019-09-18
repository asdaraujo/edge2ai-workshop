#!/bin/bash
set -u
set -e

if [ $# -lt 1 ]; then
  echo "Syntax: $0 command"
  exit 1
fi

BASE_DIR=$(cd $(dirname $0); pwd -L)
LOG_DIR=$BASE_DIR/logs
LOG_FILE=$LOG_DIR/command.$(date +%s).log

if [ ! -f .key.file.name -o ! -f .instance.list ]; then
  $BASE_DIR/list-details.sh > /dev/null
fi
KEY_FILE=$BASE_DIR/$(cat $BASE_DIR/.key.file.name)

cmd=("$@")
for line in $(awk '{print $1":"$3}' .instance.list); do
  cluster_name=$(echo "$line" | awk -F: '{print $1}')
  public_ip=$(echo "$line" | awk -F: '{print $2}')
  ssh -q -o StrictHostKeyChecking=no -i $KEY_FILE centos@$public_ip "${cmd[@]}" 2>&1 | sed "s/^/$cluster_name: /" | tee -a $LOG_FILE &
done

wait
echo "Log file: $LOG_FILE"
