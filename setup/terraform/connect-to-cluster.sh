#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

if [ $# != 2 ]; then
  echo "Syntax: $0 <namespace> <cluster_number>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
CLUSTER_ID=$2
load_env $NAMESPACE

if [ ! -s $TF_VAR_ssh_private_key ]; then
  echo "Private key not found: $TF_VAR_ssh_private_key"
  exit 1
fi

ssh -o StrictHostKeyChecking=no -i $TF_VAR_ssh_private_key $TF_VAR_ssh_username@$(public_dns $CLUSTER_ID)
