#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common-basics.sh

if [[ $# -lt 1 ]]; then
  echo "Syntax: $0 <namespace> [action]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
ACTION=${2:-list}
if [[ $ACTION == "enddate" ]]; then
  if [[ $# -ne 3 ]]; then
    echo "Syntax: $0 <namespace> enddate <MMDDYYYY>"
    show_namespaces
    exit 1
  else
    ENDDATE=$3
  fi
fi

source $BASE_DIR/common.sh

load_env $NAMESPACE

function list_instances() {
  local instance_ids=$1
  printf "%-20s %-10s %-40s %-15s %s\n" $(echo "Id State Name Owner EndDate"; aws ec2 describe-instances --instance-ids $instance_ids | \
  jq -r '.Reservations[].Instances[] | "\(.InstanceId) \(.State.Name) \(.Tags[]? | select(.Key == "Name").Value) \(.Tags[]? | select(.Key == "owner").Value) \(.Tags[]? | select(.Key == "enddate").Value)"' | sort -k2)
}

function yamlize() {
  python -c 'import json, yaml, sys; print(yaml.dump(json.loads(sys.stdin.read())))'
}

INSTANCE_IDS="$(cluster_instances | cluster_attr id) $(web_instance | web_attr id) $(ipa_instance | ipa_attr id)"

if [[ $ACTION == "list" ]]; then
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "terminate" ]]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS | yamlize
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "stop" ]]; then
  aws ec2 stop-instances --instance-ids $INSTANCE_IDS | yamlize
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "start" ]]; then
  aws ec2 start-instances --instance-ids $INSTANCE_IDS | yamlize
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "enddate" ]]; then
  aws ec2 create-tags --resources $INSTANCE_IDS --tags Key=enddate,Value=$ENDDATE
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "check" ]]; then
  for id in $INSTANCE_IDS; do
    aws ec2 describe-instance-attribute --instance-id $id --attribute disableApiTermination | jq -r '"\(.InstanceId) \(.DisableApiTermination.Value)"'
  done
elif [[ $ACTION == "protect" ]]; then
  for id in $INSTANCE_IDS; do
    echo "Enabling protection for instance $id"
    aws ec2 modify-instance-attribute --instance-id $id --disable-api-termination
  done
elif [[ $ACTION == "unprotect" ]]; then
  for id in $INSTANCE_IDS; do
    echo "Disabling protection for instance $id"
    aws ec2 modify-instance-attribute --instance-id $id --no-disable-api-termination
  done
elif [[ $ACTION == "describe" ]]; then
  aws ec2 describe-instances --instance-ids $INSTANCE_IDS | yamlize
fi