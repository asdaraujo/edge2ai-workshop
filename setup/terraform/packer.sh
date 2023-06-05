#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1

source $BASE_DIR/lib/common.sh

mkdir -p $BASE_DIR/logs
(
set -o errexit
set -o nounset
set -o pipefail

packer build \
  -var "aws_profile=$TF_VAR_aws_profile" \
  -var "aws_access_key=$TF_VAR_aws_access_key_id" \
  -var "aws_secret_key=$TF_VAR_aws_secret_access_key" \
  -var "aws_region=$TF_VAR_aws_region" \
  -var "aws_az=$TF_VAR_aws_az" \
  -var "ssh_username=$TF_VAR_ssh_username" \
  -var "ssh_password=$TF_VAR_ssh_password" \
  -var "base_ami=$TF_VAR_base_ami" \
  -var "instance_type=$TF_VAR_cluster_instance_type" \
  -var "owner=$TF_VAR_owner" \
  -var "project=$TF_VAR_project" \
  -var "enddate=$TF_VAR_enddate" \
  -var "namespace=$NAMESPACE" \
  packer.json

log "AMI created successfully"
) 2>&1 | tee $BASE_DIR/logs/packer.log.${NAMESPACE:-unknown}.$(date +%Y%m%d%H%M%S)
