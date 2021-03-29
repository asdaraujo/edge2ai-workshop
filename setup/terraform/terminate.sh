#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
CAFFEINATE_ME=1
source $BASE_DIR/common.sh

mkdir -p $BASE_DIR/logs
(
set -e
set -u
set -o pipefail

if [ $# -lt 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

if [[ ${2:-you-are-wise} != "destroy-without-confirmation-do-not-try-this-at-home" ]]; then
  echo "WARNING: if you continue all the instances for the bootcamp environment will be destroyed!!"
  echo -en "\nIf you are certain that you want to destroy the environment, type YES: "
  read confirm
  if [ "$confirm" != "YES" ]; then
    echo "${C_RED}WARNING: Skipping termination. If you really want to destroy, run it again and answer"
    echo "         the prompt with YES (all caps)."
    echo "Bye...${C_NORMAL}"
    exit
  fi
fi

log "Destroying instances"
(cd $BASE_DIR && run_terraform init)
(cd $BASE_DIR && run_terraform destroy -parallelism=1000 -auto-approve -state=$TF_STATE)

log "Cleaning up"
rm -f $NAMESPACE_DIR/{.instance.list,.instance.web}
[[ -f $TF_STATE ]] && mv $TF_STATE ${TF_STATE}.OLD.$(date +%Y%m%d%H%M%S)
[[ -f ${TF_STATE}.backup ]] && mv ${TF_STATE}.backup ${TF_STATE}.backup.OLD.$(date +%Y%m%d%H%M%S)
[[ -f $TF_JSON_FILE ]] && mv $TF_JSON_FILE ${TF_JSON_FILE}.OLD.$(date +%Y%m%d%H%M%S)
delete_key_pairs

log "Deployment destroyed successfully"
) 2>&1 | tee $BASE_DIR/logs/terminate.log.${1:-unknown}.$(date +%Y%m%d%H%M%S)
