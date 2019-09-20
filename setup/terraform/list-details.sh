#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
. $BASE_DIR/common.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

TF_JSON_FILE=$BASE_DIR/.tf.json.$$
trap "rm -f $TF_JSON_FILE" 0

terraform show -json $NAMESPACE_DIR/terraform.state > $TF_JSON_FILE

function web_instance() {
  cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_instance" and .name == "web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
}

function cluster_instances() {
  cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_instance" and .name != "web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
}

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

echo "Web Server:       http://$(web_instance | awk '{print $3}')"
echo "Web Server admin: $TF_VAR_web_server_admin_email"
echo ""

echo "SSH username: $TF_VAR_ssh_username"
echo ""

echo "WEB SERVER VM:"
echo "=============="
printf "%-40s %-55s %-15s %-15s\n" "Web Server Name" "Public DNS Name" "Public IP" "Private IP"
web_instance | while read name public_dns public_ip private_ip; do
  printf "%-40s %-55s %-15s %-15s\n" "$name" "$public_dns" "$public_ip" "$private_ip"
done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' | tee $WEB_INSTANCE_LIST_FILE
echo ""

echo "CLUSTER VMS:"
echo "============"
printf "%-40s %-55s %-15s %-15s\n" "Cluster Name" "Public DNS Name" "Public IP" "Private IP"
cluster_instances | while read name public_dns public_ip private_ip; do
  printf "%-40s %-55s %-15s %-15s\n" "$name" "$public_dns" "$public_ip" "$private_ip"
done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//' | tee $INSTANCE_LIST_FILE

echo ""
