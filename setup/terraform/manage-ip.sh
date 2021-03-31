#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

function syntax() {
  echo "Syntax: $0 <namespace> <"\""add"\""|"\""remove"\""> <ip_address>"
  show_namespaces
}

IP_FILE=/tmp/sync-ip-addresses.$$

function cleanup() {
  rm -f $IP_FILE
}

if [[ $# -lt 3 || ( ${2:-} != "add" && ${2:-} != "remove" ) ]]; then
  syntax
  exit 1
fi
NAMESPACE=$1
ACTION=$2
IP_ADDRESS=$3
load_env $NAMESPACE

if [[ $(echo "$IP_ADDRESS" | tr "a-z" "A-Z") == "MYIP" ]]; then
  IP_ADDRESS=$(curl -s ifconfig.me)
fi

cluster_sg=$(security_groups cluster)
web_sg=$(security_groups web)

if [[ $ACTION == "add" ]]; then
  add_ingress "$web_sg" "${IP_ADDRESS}/32" tcp 80 "MANUAL" force
  add_ingress "$cluster_sg" "${IP_ADDRESS}/32" tcp 0-65535 "MANUAL" force
elif [[ $ACTION == "remove" ]]; then
  remove_ingress "$web_sg" "${IP_ADDRESS}/32" tcp 80 force
  remove_ingress "$cluster_sg" "${IP_ADDRESS}/32" tcp 0-65535 force
fi
