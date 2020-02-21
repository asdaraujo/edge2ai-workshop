#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

if [ $# -gt 1 ]; then
  echo "Syntax: $0 [namespace]"
  show_namespaces
  exit 1
fi
NAMESPACE=${1:-}

function web_instance() {
  if [ -s $TF_JSON_FILE ]; then
    cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.address == "aws_instance.web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
  fi
}

function cluster_instances() {
  if [ -s $TF_JSON_FILE ]; then
    cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.address == "aws_instance.cluster") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
  fi
}

function enddate() {
  if [ -s $TF_JSON_FILE ]; then
    cat $TF_JSON_FILE | jq -r '.values.root_module.resources[0].values.tags.enddate' | sed 's/null//'
  fi
}

function show_details() {
  local namespace=$1
  local summary_only=${2:-no}

  load_env $namespace

  TF_JSON_FILE=$BASE_DIR/.tf.json.$$
  trap "rm -f $TF_JSON_FILE" 0

  rm -f $TF_JSON_FILE
  mkdir -p $NAMESPACE_DIR
  set +e
  terraform show -json $NAMESPACE_DIR/terraform.state > $TF_JSON_FILE 2>/dev/null
  set +e

  web_instance | while read name public_dns public_ip private_ip; do
    printf "%-40s %-55s %-15s %-15s\n" "$name" "$public_dns" "$public_ip" "$private_ip"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > $WEB_INSTANCE_LIST_FILE

  cluster_instances | while read name public_dns public_ip private_ip; do
    printf "%-40s %-55s %-15s %-15s\n" "$name" "$public_dns" "$public_ip" "$private_ip"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > $INSTANCE_LIST_FILE

  if [ -s $WEB_INSTANCE_LIST_FILE ]; then
    web_server="http://$(web_instance | awk '{print $3}')"
  else
    web_server="-"
  fi

  local enddate=$(enddate)
  local remaining_days=""
  local warning=""
  if [ "$enddate" != "" ]; then
    remaining_days=$(remaining_days "$enddate")
    if [ "$remaining_days" -lt 2 ]; then
      warning=$(echo -e "${C_RED}==> ATTENTION: Your instances will expire and be destroyed in $remaining_days days${C_NORMAL}")
    fi
  fi

  if [ "$summary_only" != "no" ]; then
    printf "%-25s %-40s %10d  %8s  %9s %s\n" "$namespace" "$web_server" "$(cat $INSTANCE_LIST_FILE | wc -l)" "$enddate" "$remaining_days" "$warning"
  else
    if [ -s "$TF_VAR_web_ssh_private_key" ]; then
      echo "WEB SERVER Key file: $TF_VAR_web_ssh_private_key"
      echo "WEB SERVER Key contents:"
      cat $TF_VAR_web_ssh_private_key
    else
      echo "WEB SERVER Key file is not available."
    fi
    echo ""

    if [ -s "$TF_VAR_ssh_private_key" ]; then
      echo "Key file: $TF_VAR_ssh_private_key"
      echo "Key contents:"
      cat $TF_VAR_ssh_private_key
    else
      echo "Key file is not available."
    fi
    echo ""

    echo "Web Server:       $web_server"
    echo "Web Server admin: $TF_VAR_web_server_admin_email"
    echo ""

    echo "SSH username: $TF_VAR_ssh_username"
    echo ""

    echo "WEB SERVER VM:"
    echo "=============="
    printf "%-40s %-55s %-15s %-15s\n" "Web Server Name" "Public DNS Name" "Public IP" "Private IP"
    cat $WEB_INSTANCE_LIST_FILE
    echo ""

    echo "CLUSTER VMS:"
    echo "============"
    printf "%-40s %-55s %-15s %-15s\n" "Cluster Name" "Public DNS Name" "Public IP" "Private IP"
    cat $INSTANCE_LIST_FILE

    echo ""
    if [ "$warning" != "" ]; then
      echo "  $warning"
      echo ""
    fi

    if [ "${DEBUG_DETAILS:-}" != "" ]; then
      jq -r '.' $TF_JSON_FILE
    fi
  fi
}

if [ "$NAMESPACE" == "" ]; then
  printf "%-25s %-40s %10s  %8s  %9s\n" "Namespace" "Web Server" "# of VMs" "End Date" "Days Left"
  for namespace in $(get_namespaces); do
    show_details $namespace yes
  done
  echo ""
  echo "${C_YELLOW}    To list the full details for a particular namespace, use:"
  echo ""
  echo "          ./list-details.sh <namespace>"
  echo "${C_NORMAL}"
else
  show_details $NAMESPACE
fi
