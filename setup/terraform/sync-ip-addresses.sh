#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [[ $# -lt 1 || ($# -eq 2 && $2 != "--no_refresh") ]]; then
  echo "Syntax: $0 <namespace> ["\""--no_refresh"\""]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
NO_REFRESH=${2:-}

if [[ $NO_REFRESH == "" ]]; then
  NEED_CLOUD_SESSION=1
fi
source $BASE_DIR/lib/common.sh

IP_FILE=/tmp/sync-ip-addresses.$$

function cleanup() {
  rm -f $IP_FILE
}

cluster_sg=$(security_groups cluster)
web_sg=$(security_groups web)

if [[ $NO_REFRESH == "" ]]; then
  refresh_tf_state
  ensure_tf_json_file
fi

# Ensure admin has access to web server for their local machine
add_ingress "$web_sg" "$(get_public_ip)/32" tcp 80 "WEB_ADMIN" force

get_ips > $IP_FILE
for ip in $(cat $IP_FILE); do
  add_ingress "$web_sg" "${ip}/32" tcp 80 "WORKSHOP_USER" force
  add_ingress "$cluster_sg" "${ip}/32" all all "WORKSHOP_USER" force
done

for sg in "$web_sg" "$cluster_sg"; do
  get_ingress "$sg" "" "" "" "WORKSHOP_USER" | while read cidr protocol port; do
    ip=${cidr%/*}
    grep -q "^${ip}$" $IP_FILE || remove_ingress "$sg" "$cidr" "$protocol" "$port" force
  done
done
