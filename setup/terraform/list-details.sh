#!/bin/bash

TF_JSON_FILE=.tf.json.$$
trap "rm -f $TF_JSON_FILE" 0

terraform show -json > $TF_JSON_FILE

KEY_FILE=$(cat $TF_JSON_FILE | terraform show -json | jq -r '.values[].resources[] | select(.address == "aws_key_pair.bootcamp_key_pair").values.key_name').pem
echo $KEY_FILE > .key.file.name
echo "Key file: $KEY_FILE"
echo "Key contents:"
cat $KEY_FILE
echo ""
echo "Username: centos"
echo ""
printf "%-40s %-55s %-15s\n" "Cluster Name" "Public DNS Name" "Public IP"
cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.type == "aws_instance") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip)"' | while read name public_dns public_ip; do
  printf "%-40s %-55s %-15s\n" "$name" "$public_dns" "$public_ip" | tee .instance.list
done | sed 's/\([^ ]*-\)\([0-9]*\)\( .*\)/\1\2\3 \2/' | sort -k4n | sed 's/ [0-9]*$//'

KEY_FILE=$BASE_DIR/$(terraform state show "aws_key_pair.bootcamp_key_pair" -no-color | grep "^ *key_name " | awk -F\" '{print $2}').pem
