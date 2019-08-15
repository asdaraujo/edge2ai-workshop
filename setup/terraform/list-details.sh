#!/bin/bash

TF_JSON_FILE=.tf.json.$$
trap "rm -f $TF_JSON_FILE" 0

terraform show -json > $TF_JSON_FILE

KEY_FILE=$(cat $TF_JSON_FILE | terraform show -json | jq -r '.values[].resources[] | select(.address == "aws_key_pair.bootcamp_key_pair").values.key_name').pem
echo $KEY_FILE > .key.file.name
echo "Key file: $KEY_FILE"
echo ""

printf "%-40s %-55s %-15s %s\n" "Cluster Name" "Public DNS Name" "Public IP" "Private DNS Name"
cat $TF_JSON_FILE | jq -r '.values[].resources[] | select(.type == "aws_instance") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_dns)"' | while read name public_dns public_ip private_dns; do
  printf "%-40s %-55s %-15s %s\n" "$name" "$public_dns" "$public_ip" "$private_dns" | tee .instance.list
done

KEY_FILE=$BASE_DIR/$(terraform state show "aws_key_pair.bootcamp_key_pair" -no-color | grep "^ *key_name " | awk -F\" '{print $2}').pem
