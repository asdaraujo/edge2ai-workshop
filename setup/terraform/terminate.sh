#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh
mkdir -p $BASE_DIR/logs
(
set -e
set -u
set -o pipefail

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

echo "WARNING: if you continue all the instances for the bootcamp environment will be destroyed!!"
echo -en "\nIf you are certain that you want to destroy the environment, type YES: "
read confirm
if [ "$confirm" != "YES" ]; then
  echo "${C_RED}WARNING: Skipping termination. If you really want to destroy, run it again and answer"
  echo "         the prompt with YES (all caps)."
  echo "Bye...${C_NORMAL}"
  exit
fi

log "Destroying instances"
terraform init
terraform destroy -auto-approve -state=$NAMESPACE_DIR/terraform.state

log "Cleaning up"
rm -f $NAMESPACE_DIR/{.instance.list,.instance.web}
delete_key_pairs

log "Deployment destroyed successfully"
) 2>&1 | tee $BASE_DIR/logs/terminate.log.${1:-unknown}.$(date +%Y%m%d%H%M%S)
