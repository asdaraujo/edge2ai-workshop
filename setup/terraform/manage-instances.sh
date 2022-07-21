#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

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

NEED_CLOUD_SESSION=1
source $BASE_DIR/lib/common.sh

function list_instances() {
  local instance_ids=$1
  printf "%-12s %-15s %-8s %-40s %s\n" $(echo "State Owner EndDate Name Id"; list_cloud_instances "$instance_ids")
}

INSTANCE_IDS="$(cluster_instances | cluster_attr id) $(web_instance | web_attr id) $(ipa_instance | ipa_attr id)"

if [[ $ACTION == "list" ]]; then
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "terminate" ]]; then
  terminate_instances "$INSTANCE_IDS"
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "stop" ]]; then
  stop_instances "$INSTANCE_IDS"
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "start" ]]; then
  start_instances "$INSTANCE_IDS"
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "enddate" ]]; then
  set_instances_tag "$INSTANCE_IDS" enddate "$ENDDATE"
  list_instances "$INSTANCE_IDS"
elif [[ $ACTION == "is_protected" ]]; then
  for id in $INSTANCE_IDS; do
    printf "%-5s %s\n" "$(is_instance_protected $id)" "$id"
  done
elif [[ $ACTION == "protect" ]]; then
  for id in $INSTANCE_IDS; do
    echo "Enabling protection for instance $id"
    protect_instance $id
  done
elif [[ $ACTION == "unprotect" ]]; then
  for id in $INSTANCE_IDS; do
    echo "Disabling protection for instance $id"
    unprotect_instance $id
  done
elif [[ $ACTION == "describe" ]]; then
  describe_instances "$INSTANCE_IDS"
fi