#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common-basics.sh

function syntax() {
  echo "Syntax: $0 <namespace> [new_registration_code] [web_ip_adress] [admin_email] [admin_password]"
  show_namespaces
}

if [ $# -lt 1 ]; then
  syntax
  exit 1
fi
NAMESPACE=$1

source $BASE_DIR/common.sh

load_env $NAMESPACE

CODE=${2:-}
WEB_IP_ADDRESS=${3:-}
ADMIN_EMAIL=${4:-$TF_VAR_web_server_admin_email}
ADMIN_PWD=${5:-$TF_VAR_web_server_admin_password}

if [ "$WEB_IP_ADDRESS" == "" ]; then
  WEB_IP_ADDRESS=$( web_instance | web_attr public_ip )
fi

if [[ ${WEB_IP_ADDRESS} == "" ]]; then
  echo "There's no web server. Skipping update."
  exit
fi

ensure_registration_code "$CODE"
update_web_server registration.code "$TF_VAR_registration_code" true

echo "Registration code set to: $TF_VAR_registration_code"
