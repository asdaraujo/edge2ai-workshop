#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

function cleanup() {
  rm -f $INSTANCE_LIST_FILE $WEB_INSTANCE_LIST_FILE
}

EC2_PRICES_URL_TEMPLATE=https://raw.githubusercontent.com/yeo/ec2.shop/master/data/REGION-ondemand.json
WEB_INSTANCE_TYPE=t2.medium
INSTANCE_LIST_FILE=/tmp/.instance.list.$$
WEB_INSTANCE_LIST_FILE=/tmp/.instance.web.$$

if [ $# -gt 1 ]; then
  echo "Syntax: $0 [namespace]"
  show_namespaces
  exit 1
fi
NAMESPACE=${1:-}

function show_costs() {
  local ec2_prices_url=$(echo "$EC2_PRICES_URL_TEMPLATE" | sed "s/REGION/$TF_VAR_aws_region/")
  local tmp_file=/tmp/list-details.cost.$$

  local ret=$(curl -w "%{http_code}" "$ec2_prices_url" -o $tmp_file --stderr /dev/null)
  if [[ $ret == 200 ]]; then
    local web_price=$(jq -r '.prices[] | select(.attributes["aws:ec2:instanceType"] == "'"$WEB_INSTANCE_TYPE"'").price.USD' $tmp_file)
    local cluster_price=$(jq -r '.prices[] | select(.attributes["aws:ec2:instanceType"] == "'"$TF_VAR_cluster_instance_type"'").price.USD' $tmp_file)
    echo -e "\nCLOUD COSTS:"
    echo "============"
    printf "%-11s %-15s %3s %15s %15s %15s\n" "Purpose" "Instance Type" "Qty" "Unit USD/Hr" "Total USD/Hr" "Total USD/Day"
    printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "Web" "$WEB_INSTANCE_TYPE" "1" "$web_price" "$web_price" "$(calc "24*$web_price")"
    printf "%-11s %-15s %3d %15.4f %15.4f %15.4f\n" "Cluster" "$TF_VAR_cluster_instance_type" "$TF_VAR_cluster_count" "$cluster_price" "$(calc "$TF_VAR_cluster_count*$cluster_price")" "$(calc "24*$TF_VAR_cluster_count*$cluster_price")"
    printf "%-11s %35s %15.4f ${C_BG_MAGENTA}${C_WHITE}%15.4f${C_NORMAL}\n" "GRAND TOTAL" "---------------------------------->" "$(calc "$web_price+$TF_VAR_cluster_count*$cluster_price")" "$(calc "24*($web_price+$TF_VAR_cluster_count*$cluster_price)")"
  else
    echo -e "\nUnable to retrieve cloud costs."
  fi
  rm -f $tmp_file
}

function show_details() {
  local namespace=$1
  local summary_only=${2:-no}

  load_env $namespace

  ensure_tf_json_file

  web_instance | while read name public_dns public_ip private_ip; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "$(is_stoppable web 0)"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > $WEB_INSTANCE_LIST_FILE

  cluster_instances | while read index name public_dns public_ip private_ip; do
    printf "%-40s %-55s %-15s %-15s %-9s\n" "$name" "$public_dns" "$public_ip" "$private_ip" "$(is_stoppable cluster $index)"
  done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' > $INSTANCE_LIST_FILE

  if [ -s $WEB_INSTANCE_LIST_FILE ]; then
    web_server="http://$(web_instance | web_attr public_ip)"
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

    echo "Web Server:        $web_server"
    echo "Registration code: $(registration_code)"
    echo "Web Server admin:  $TF_VAR_web_server_admin_email"
    echo ""

    echo "SSH username: $TF_VAR_ssh_username"
    echo ""

    echo "WEB SERVER VM:"
    echo "=============="
    printf "%-40s %-55s %-15s %-15s %-9s\n" "Web Server Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
    cat $WEB_INSTANCE_LIST_FILE
    echo ""

    echo "CLUSTER VMS:"
    echo "============"
    printf "%-40s %-55s %-15s %-15s %-9s\n" "Cluster Name" "Public DNS Name" "Public IP" "Private IP" "Stoppable"
    cat $INSTANCE_LIST_FILE

    if [[ $summary_only == "no" ]]; then
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
  printf "%-25s %-40s %10s  %8s  %9s\n" "Namespace" "Web Server" "# of VMs" "End Date" "Days Left"
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
