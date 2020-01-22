#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

function syntax() {
  echo "Syntax: $0 <namespace> [web_ip_adress] [admin_email] [admin_password] [admin_full_name]"
  show_namespaces
}

if [ $# -lt 1 ]; then
  syntax
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

WEB_IP_ADDRESS=${2:-}
ADMIN_EMAIL=${3:-$TF_VAR_web_server_admin_email}
ADMIN_PWD=${4:-$TF_VAR_web_server_admin_password}
ADMIN_NAME=${5:-$TF_VAR_owner}

if [ ! -s $TF_VAR_ssh_private_key ]; then
  echo "ERROR: File $TF_VAR_ssh_private_key does not exist."
  exit 1
fi

if [ ! -s $INSTANCE_LIST_FILE ]; then
  echo "ERROR: File $INSTANCE_LIST_FILE does not exist."
  exit 1
fi

if [ "$WEB_IP_ADDRESS" == "" ]; then
  if [ -s $WEB_INSTANCE_LIST_FILE ]; then
    WEB_IP_ADDRESS=$( awk '{print $3}' $WEB_INSTANCE_LIST_FILE )
  else
    echo "ERROR: File $WEB_INSTANCE_LIST_FILE doesn't exist and WEB Server IP address wasn't specified."
    syntax
    exit 1
  fi
fi

curl -k -H "Content-Type: application/json" -X POST \
  -d '{
       "email":"'"$ADMIN_EMAIL"'",
       "full_name": "'"$ADMIN_NAME"'",
       "company": "",
       "password": "'"$ADMIN_PWD"'"
      }' \
  "http://${WEB_IP_ADDRESS}/api/admins" 2>/dev/null

awk '{print $2" "$3}' $INSTANCE_LIST_FILE | while read public_dns public_ip; do
  curl -k -H "Content-Type: application/json" -X POST \
    -u "${ADMIN_EMAIL}:${ADMIN_PWD}" \
    -d '{
         "ip_address":"'"${public_ip}"'",
         "hostname":"'"${public_dns}"'",
         "ssh_user": "'"$TF_VAR_ssh_username"'",
         "ssh_password": "'"$TF_VAR_ssh_password"'",
         "ssh_private_key": "'"$(cat $TF_VAR_ssh_private_key | tr "\n" "#" | sed 's/#/\\n/g')"'"}' \
    "http://${WEB_IP_ADDRESS}/api/clusters" 2>/dev/null
done
