#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common-basics.sh

if [ $# -lt 2 ]; then
  echo "Syntax: $0 <namespace> command"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
CLUSTER_ID=$2

source $BASE_DIR/common.sh

load_env $NAMESPACE

LOG_DIR=$BASE_DIR/logs
LOG_FILE=$LOG_DIR/command.$(date +%s).log

shift 1
cmd=("$@")
for cluster_id in $(cluster_instances | cluster_attr index); do
  cluster_name="$(cluster_instances $cluster_id | cluster_attr name): "
  public_ip="$(cluster_instances $cluster_id | cluster_attr public_ip)"
  ssh -q -o StrictHostKeyChecking=no -i $TF_VAR_ssh_private_key $TF_VAR_ssh_username@$public_ip "${cmd[@]}" 2>&1 | \
    sed "s/^/${cluster_name}/" | tee $LOG_FILE | sed "s/^[^:]*:/${C_NORMAL}${C_BOLD}&${C_NORMAL}/" &
done

wait
echo "Log file: $LOG_FILE"
