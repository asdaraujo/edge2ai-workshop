#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [[ $# -gt 2 || ($# -eq 2 && $2 != "--refresh") ]]; then
  echo "Syntax: $0 [namespace] [--refresh]"
  show_namespaces
  exit 1
fi
NAMESPACE=${1:-}
REFRESH=${2:-}

if [[ $REFRESH != "" ]]; then
  NEED_CLOUD_SESSION=1
fi
source $BASE_DIR/lib/common.sh

function cleanup() {
  rm -f ${INSTANCE_LIST_FILE}* ${WEB_INSTANCE_LIST_FILE}* ${IPA_INSTANCE_LIST_FILE}*
}

INSTANCE_LIST_FILE=/tmp/.instance.list.$$
ECS_LIST_FILE=/tmp/.ecs.list.$$
WEB_INSTANCE_LIST_FILE=/tmp/.instance.web.$$
IPA_INSTANCE_LIST_FILE=/tmp/.instance.ipa.$$

function show_costs() {
  local cluster_price=0
  local web_price=0
  local ipa_price=0
  local ecs_price=0
  local cluster_instance_type=$(cluster_instances 0 | cluster_attr instance_type)
  if [[ $cluster_instance_type != "" ]]; then
    cluster_price=$(get_instance_hourly_cost $cluster_instance_type)
  fi
  local web_instance_type=$(web_instance | web_attr instance_type)
  if [[ $web_instance_type != "" ]]; then
    web_price=$(get_instance_hourly_cost $web_instance_type)
  fi
  local ipa_instance_type=$(ipa_instance | web_attr instance_type)
  if [[ $ipa_instance_type != "" ]]; then
    ipa_price=$(get_instance_hourly_cost $ipa_instance_type)
  fi
  local ecs_instance_type=$(ecs_instances 0 | ecs_attr instance_type)
  if [[ $ecs_instance_type != "" ]]; then
    ecs_price=$(get_instance_hourly_cost $ecs_instance_type)
  fi

  if [[ ($cluster_instance_type == "" || $cluster_price != "0") && ($web_instance_type == "" || $web_price != "0") && ($ipa_instance_type == "" || $ipa_price != "0") && ($ecs_instance_type == "" || $ecs_price != "0") ]]; then
    echo -e "\nCLOUD COSTS:"
    echo "============"
    printf "%-11s %-15s %3s %15s %15s %15s\n" "Purpose" "Instance Type" "Qty" "Unit USD/Hr" "Total USD/Hr" "Total USD/Day"
    if [[ $web_instance_type != "" ]]; then
      printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "Web" "$web_instance_type" "1" "$web_price" "$web_price" "$(calc "24*$web_price")"
    fi
    if [[ $ipa_instance_type != "" ]]; then
      printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "IPA" "$ipa_instance_type" "1" "$ipa_price" "$ipa_price" "$(calc "24*$ipa_price")"
    fi
    if [[ $ecs_instance_type != "" ]]; then
      printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "ECS" "$ecs_instance_type" "$TF_VAR_cluster_count" "$ecs_price" "$(calc "$TF_VAR_cluster_count*$ecs_price")" "$(calc "24*$TF_VAR_cluster_count*$ecs_price")"
    fi
    if [[ $cluster_instance_type != "" ]]; then
      printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "Cluster" "$cluster_instance_type" "$TF_VAR_cluster_count" "$cluster_price" "$(calc "$TF_VAR_cluster_count*$cluster_price")" "$(calc "24*$TF_VAR_cluster_count*$cluster_price")"
    fi
    printf "%-11s %35s %15.4f ${C_BG_MAGENTA}${C_WHITE}%15.4f${C_NORMAL}\n" "GRAND TOTAL" "---------------------------------->" "$(calc "$web_price+$ipa_price+$TF_VAR_cluster_count*$cluster_price+$TF_VAR_cluster_count*$ecs_price")" "$(calc "24*($web_price+$ipa_price+$TF_VAR_cluster_count*$cluster_price+$TF_VAR_cluster_count*$ecs_price)")"
  else
    echo -e "\nUnable to retrieve cloud costs."
  fi
}

function show_details() {
  local namespace=$1
  local show_summary=${2:-no}

  local warning=""
  if [[ $show_summary == "no" ]]; then
    load_env $namespace
  else
    local tmp_file=/tmp/.${namespace}.$$
    SKIP_CLOUD_LOGIN=1 load_env $namespace > $tmp_file 2>&1
    if [[ -s $tmp_file ]]; then
      warning="$(cat $tmp_file | sed 's/\.$//'). "
    fi
    rm -f $tmp_file
  fi

  if [[ $REFRESH != "" ]]; then
    refresh_tf_state
  fi
  ensure_tf_json_file

  web_instance | web_attr name public_dns public_ip private_ip is_stoppable | \
  while read name public_dns public_ip private_ip is_stoppable; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "$is_stoppable"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > ${WEB_INSTANCE_LIST_FILE}.$namespace

  ipa_instance | ipa_attr name public_dns public_ip private_ip | \
  while read name public_dns public_ip private_ip; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "Yes"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > ${IPA_INSTANCE_LIST_FILE}.$namespace

  ecs_instances | ecs_attr name public_dns public_ip private_ip is_stoppable | \
  while read name public_dns public_ip private_ip is_stoppable; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "$is_stoppable"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > ${ECS_LIST_FILE}.$namespace

  cluster_instances | cluster_attr name public_dns public_ip private_ip is_stoppable | \
  while read name public_dns public_ip private_ip is_stoppable; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "$is_stoppable"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > ${INSTANCE_LIST_FILE}.$namespace

  if [ -s ${WEB_INSTANCE_LIST_FILE}.$namespace ]; then
    web_server="http://$(web_instance | web_attr public_ip)"
  else
    web_server="-"
  fi

  local enddate=$(enddate)
  local remaining_days=""
  if [ "$enddate" != "" ]; then
    remaining_days=$(remaining_days "$enddate")
    if [ "$remaining_days" -lt 2 ]; then
      warning="${warning}$(echo -e "${C_RED}==> ATTENTION: Your instances will expire and be destroyed in $remaining_days days${C_NORMAL}")"
    fi
  fi

  if [ "$show_summary" == "yes" ]; then
    printf "%-25s %-30s %-30s %10d  %8s  %9s %s\n" "$namespace" "$web_server" "$(awk 'NR==1{print $2}' ${INSTANCE_LIST_FILE}.$namespace)" "$(cat ${INSTANCE_LIST_FILE}.$namespace | wc -l)" "$enddate" "$remaining_days" "$warning"
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

    echo "Web Server:        $web_server"
    echo "Registration code: $(registration_code)"
    echo "Web Server admin:  $TF_VAR_web_server_admin_email"
    echo ""

    echo "SSH username: $TF_VAR_ssh_username"
    echo ""

    if [[ -s ${WEB_INSTANCE_LIST_FILE}.$namespace ]]; then
      echo "WEB SERVER VM:"
      echo "=============="
      printf "%-40s %-55s %-15s %-15s %-9s\n" "Web Server Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
      cat ${WEB_INSTANCE_LIST_FILE}.$namespace
      echo ""
    fi

    if [[ -s ${IPA_INSTANCE_LIST_FILE}.$namespace ]]; then
      echo "IPA SERVER VM:"
      echo "=============="
      printf "%-40s %-55s %-15s %-15s %-9s\n" "IPA Server Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
      cat ${IPA_INSTANCE_LIST_FILE}.$namespace
      echo ""
    fi

    if [[ -s ${ECS_LIST_FILE}.$namespace ]]; then
      echo "ECS SERVER VM:"
      echo "=============="
      printf "%-40s %-55s %-15s %-15s %-9s\n" "ECS Server Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
      cat ${ECS_LIST_FILE}.$namespace
      echo ""
    fi

    if [[ -s ${INSTANCE_LIST_FILE}.$namespace ]]; then
      echo "CLUSTER VMS:"
      echo "============"
      printf "%-40s %-55s %-15s %-15s %-9s\n" "Cluster Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
      cat ${INSTANCE_LIST_FILE}.$namespace
    fi

    if [[ $show_summary == "no" ]]; then
      show_costs
    fi

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
  printf "%-25s %-30s %-30s %10s  %8s  %9s\n" "Namespace" "Web Server" "Cluster 0" "# of VMs" "End Date" "Days Left"
  tmp_dir=/tmp/list-details.$$
  rm -rf $tmp_dir
  mkdir $tmp_dir
  for namespace in $(get_namespaces); do
    show_details $namespace yes > $tmp_dir/$namespace &
  done
  wait
  cat $tmp_dir/*
  rm -rf $tmp_dir
  echo ""
  echo "${C_YELLOW}    To list the full details for a particular namespace, use:"
  echo ""
  echo "          ./list-details.sh <namespace>"
  echo "${C_NORMAL}"
else
  show_details $NAMESPACE
fi
