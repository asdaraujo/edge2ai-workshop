#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
mkdir -p $BASE_DIR/logs
(
set -e
set -u
set -o pipefail

echo "WARNING: if you continue all the instances for the bootcamp environment will be destroyed!!"
echo -en "\nIf you are certain that you want to destroy the environment, type YES: "
read confirm
if [ "$confirm" != "YES" ]; then
  echo "WARNING: Skipping termination. If you really want to destroy, run it again and answer"
  echo "         the prompt with YES (all caps)."
  echo "Bye..."
  exit
fi

source $BASE_DIR/.env
source $BASE_DIR/common.sh

log "Destroying instances"
terraform destroy -auto-approve

log "Cleaning up"
rm -f .instance.list .key.file.name .instance.web .web.key.file.name
delete_key_pairs

log "Deployment destroyed successfully"
) 2>&1 | tee $BASE_DIR/logs/terminate.log.$(date +%Y%m%d%H%M%S)
