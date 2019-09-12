#!/bin/bash
set -u
set -e
BASE_DIR=$(cd $(dirname $0); pwd -L)

TF_JSON_FILE=.tf.json.$$
#trap "rm -f $TF_JSON_FILE" 0

. $BASE_DIR/.env

terraform show -json > $TF_JSON_FILE

function web_instance() {
  cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.type == "aws_instance" and .name == "web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip)"'
}

function cluster_instances() {
  cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.type == "aws_instance" and .name != "web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip)"'
}

function web_key_file() {
  echo $(cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.address == "aws_key_pair.workshop_web_key_pair").values.key_name').pem
}

function cluster_key_file() {
  echo $(cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.address == "aws_key_pair.workshop_key_pair").values.key_name').pem
}

WEB_KEY_FILE=$(web_key_file)
echo $WEB_KEY_FILE > .web.key.file.name
echo "WEB SERVER Key file: $WEB_KEY_FILE"
echo "WEB SERVER Key contents:"
cat $WEB_KEY_FILE
echo ""

KEY_FILE=$(cluster_key_file)
echo $KEY_FILE > .key.file.name
echo "Key file: $KEY_FILE"
echo "Key contents:"
cat $KEY_FILE
echo ""

echo "Web Server:       http://$(web_instance | awk '{print $NF}')"
echo "Web Server admin: $TF_VAR_web_server_admin_email"
echo ""

echo "SSH username: $TF_VAR_ssh_username"
echo ""

echo "WEB SERVER VM:"
echo "=============="
printf "%-40s %-55s %-15s\n" "Web Server Name" "Public DNS Name" "Public IP"
web_instance | while read name public_dns public_ip; do
  printf "%-40s %-55s %-15s\n" "$name" "$public_dns" "$public_ip"
done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' | tee .instance.web
echo ""

echo "CLUSTER VMS:"
echo "============"
printf "%-40s %-55s %-15s\n" "Cluster Name" "Public DNS Name" "Public IP"
cluster_instances | while read name public_dns public_ip; do
  printf "%-40s %-55s %-15s\n" "$name" "$public_dns" "$public_ip"
done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' | tee .instance.list

echo ""