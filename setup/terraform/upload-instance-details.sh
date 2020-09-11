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

if [ "$WEB_IP_ADDRESS" == "" ]; then
  WEB_IP_ADDRESS=$( web_instance | web_attr public_ip )
fi

wait_for_web

# Register admin user
curl -k -H "Content-Type: application/json" -X POST \
  -d '{
       "email":"'"$ADMIN_EMAIL"'",
       "full_name": "'"$ADMIN_NAME"'",
       "company": "",
       "password": "'"$ADMIN_PWD"'"
      }' \
  "http://${WEB_IP_ADDRESS}/api/admins" 2>/dev/null

# Register clusters
cluster_instances | cluster_attr index | while read cluster_id; do
  public_dns=$(cluster_instances $cluster_id | cluster_attr public_dns)
  public_ip=$(cluster_instances $cluster_id | cluster_attr public_ip)
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

