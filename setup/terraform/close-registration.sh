#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# -lt 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1

NEED_CLOUD_SESSION=1
source $BASE_DIR/lib/common.sh

echo "Closing public access to the web server"
web_sg=$(security_groups web)
remove_ingress "$web_sg" 0.0.0.0/0 tcp 80 force

echo "Processing remaining access grants"
$BASE_DIR/sync-ip-addresses.sh "${NAMESPACE}" 2>/dev/null

