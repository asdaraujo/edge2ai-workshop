#!/bin/bash
set -u
set -e
BASE_DIR=$(cd $(dirname $0); pwd -L)

. $BASE_DIR/.env

WEB_IP_ADDRESS=$( awk '{print $3}' $BASE_DIR/.instance.web )

curl -k -H "Content-Type: application/json" -X POST \
  -d '{
       "email":"'"$TF_VAR_web_server_admin_email"'",
       "full_name": "'"$TF_VAR_owner"'",
       "company": "",
       "password": "'"$TF_VAR_web_server_admin_password"'"
      }' \
  "http://${WEB_IP_ADDRESS}/api/admins" 2>/dev/null

for public_ip in $(awk '{print $3}' $BASE_DIR/.instance.list); do
  curl -k -H "Content-Type: application/json" -X POST \
    -u "${TF_VAR_web_server_admin_email}:${TF_VAR_web_server_admin_password}" \
    -d '{
         "ip_address":"'"${public_ip}"'",
         "ssh_user": "'"$TF_VAR_ssh_username"'",
         "ssh_private_key": "'"$(cat $(cat $BASE_DIR/.key.file.name) | tr "\n" "#" | sed 's/#/\\n/g')"'"}' \
    "http://${WEB_IP_ADDRESS}/api/clusters" 2>/dev/null
done
