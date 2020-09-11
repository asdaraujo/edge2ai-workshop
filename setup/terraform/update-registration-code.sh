#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

function syntax() {
  echo "Syntax: $0 <namespace> [new_registration_code] [web_ip_adress] [admin_email] [admin_password]"
  show_namespaces
}

if [ $# -lt 1 ]; then
  syntax
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

CODE=${2:-}
WEB_IP_ADDRESS=${3:-}
ADMIN_EMAIL=${4:-$TF_VAR_web_server_admin_email}
ADMIN_PWD=${5:-$TF_VAR_web_server_admin_password}

if [ "$WEB_IP_ADDRESS" == "" ]; then
  WEB_IP_ADDRESS=$( web_instance | web_attr public_ip )
fi

ensure_registration_code "$CODE"
wait_for_web

# Set registration code
curl -k -H "Content-Type: application/json" -X POST \
  -u "${ADMIN_EMAIL}:${ADMIN_PWD}" \
  -d '{
       "attr":"registration.code",
       "value": "'"$TF_VAR_registration_code"'",
       "sensitive": "true"
      }' \
  "http://${WEB_IP_ADDRESS}/api/config" 2>/dev/null

echo "Registration code set to: $TF_VAR_registration_code"
