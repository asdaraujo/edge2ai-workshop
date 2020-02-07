#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

if [ $# -lt 2 ]; then
  echo "Syntax: $0 <namespace> command"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
CLUSTER_ID=$2
load_env $NAMESPACE

LOG_DIR=$BASE_DIR/logs
LOG_FILE=$LOG_DIR/command.$(date +%s).log

shift 1
cmd=("$@")
for line in $(awk '{print $1":"$3}' $INSTANCE_LIST_FILE); do
  cluster_name="$(echo "$line" | awk -F: '{print $1}'): "
  public_ip=$(echo "$line" | awk -F: '{print $2}')
  ssh -q -o StrictHostKeyChecking=no -i $TF_VAR_ssh_private_key $TF_VAR_ssh_username@$public_ip "${cmd[@]}" 2>&1 | \
    sed "s/^/${cluster_name}/" | tee $LOG_FILE | sed "s/^[^:]*:/${C_NORMAL}${C_BOLD}&${C_NORMAL}/" &
done

wait
echo "Log file: $LOG_FILE"
