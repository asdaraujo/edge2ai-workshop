#!/bin/bash
set -u
set -e
BASE_DIR=$(cd $(dirname $0); pwd -L)

function syntax() {
  echo "Syntax: $0 [web_ip_adress] [admin_email] [admin_password] [admin_full_name]"
}

. $BASE_DIR/.env

WEB_IP_ADDRESS=${1:-}
ADMIN_EMAIL=${2:-$TF_VAR_web_server_admin_email}
ADMIN_PWD=${3:-$TF_VAR_web_server_admin_password}
ADMIN_NAME=${4:-$TF_VAR_owner}

if [ ! -s $BASE_DIR/.key.file.name ]; then
  echo "ERROR: File $BASE_DIR/.key.file.name does not exist."
  exit 1
fi

if [ ! -s $BASE_DIR/.instance.list ]; then
  echo "ERROR: File $BASE_DIR/.instance.list does not exist."
  exit 1
fi

if [ "$WEB_IP_ADDRESS" == "" ]; then
  if [ -s $BASE_DIR/.instance.web ]; then
    WEB_IP_ADDRESS=$( awk '{print $3}' $BASE_DIR/.instance.web )
  else
    echo "ERROR: File $BASE_DIR/.instance.web doesn't exist and WEB Server IP address wasn't specified."
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

for public_ip in $(awk '{print $3}' $BASE_DIR/.instance.list); do
  curl -k -H "Content-Type: application/json" -X POST \
    -u "${ADMIN_EMAIL}:${ADMIN_PWD}" \
    -d '{
         "ip_address":"'"${public_ip}"'",
         "ssh_user": "'"$TF_VAR_ssh_username"'",
         "ssh_private_key": "'"$(cat $(cat $BASE_DIR/.key.file.name) | tr "\n" "#" | sed 's/#/\\n/g')"'"}' \
    "http://${WEB_IP_ADDRESS}/api/clusters" 2>/dev/null
done
