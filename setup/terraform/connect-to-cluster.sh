#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# -lt 2 ]; then
  echo "Syntax: $0 <namespace> <cluster_number>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
CLUSTER_ID=$2

source $BASE_DIR/lib/common.sh

if [ "$CLUSTER_ID" == "web" ]; then
  PRIVATE_KEY=$TF_VAR_web_ssh_private_key
else
  PRIVATE_KEY=$TF_VAR_ssh_private_key
fi
if [ ! -s $PRIVATE_KEY ]; then
  echo "Private key not found: $PRIVATE_KEY"
  exit 1
fi

ssh -o StrictHostKeyChecking=no -i $PRIVATE_KEY $TF_VAR_ssh_username@$(public_dns $CLUSTER_ID)
