#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# -lt 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1

CAFFEINATE_ME=1
NEED_CLOUD_SESSION=1
source $BASE_DIR/lib/common.sh

mkdir -p $BASE_DIR/logs
(
set -e
set -u
set -o pipefail

if [[ ${2:-you-are-wise} != "destroy-without-confirmation-do-not-try-this-at-home" ]]; then
  echo "${C_YELLOW}WARNING: if you continue all the instances for the [$NAMESPACE] environment will be destroyed!!"
  echo -en "\nIf you are certain that you want to destroy the environment, type YES: "
  read confirm
  echo "${C_NORMAL}"
  if [ "$confirm" != "YES" ]; then
    echo "${C_RED}WARNING: Skipping termination. If you really want to destroy, run it again and answer"
    echo "         the prompt with YES (all caps)."
    echo "Bye...${C_NORMAL}"
    exit
  fi
fi

log "Destroying instances"
if [[ -f $TF_VAR_ssh_public_key ]]; then
  refresh_tf_state
fi
run_terraform destroy -parallelism=1000 -auto-approve -state=$TF_STATE

log "Cleaning up"
rm -rf $NAMESPACE_DIR/{.instance.list,.instance.web,terraform.log} $NAMESPACE_PROVIDER_DIR
[[ -f $TF_STATE ]] && mv $TF_STATE ${TF_STATE}.OLD.$(date +%Y%m%d%H%M%S)
[[ -f ${TF_STATE}.backup ]] && mv ${TF_STATE}.backup ${TF_STATE}.backup.OLD.$(date +%Y%m%d%H%M%S)
[[ -f $TF_JSON_FILE ]] && mv $TF_JSON_FILE ${TF_JSON_FILE}.OLD.$(date +%Y%m%d%H%M%S)
find $NAMESPACE_DIR -type f -name "*.OLD.*" -mtime +7 -delete
delete_key_pairs

log "Deployment destroyed successfully"
) 2>&1 | tee $BASE_DIR/logs/terminate.log.${1:-unknown}.$(date +%Y%m%d%H%M%S)
