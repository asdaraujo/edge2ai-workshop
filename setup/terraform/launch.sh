#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  abort
fi
NAMESPACE=$1
LOG_NAME=$BASE_DIR/logs/setup.log.${NAMESPACE}.$(date +%Y%m%d%H%M%S)

CAFFEINATE_ME=1
NEED_CLOUD_SESSION=1
source $BASE_DIR/lib/common.sh

mkdir -p "${BASE_DIR}"/logs
(
set -o errexit
set -o nounset
set -o pipefail

check_version
check_stack_version

function cleanup() {
  kdestroy > /dev/null 2>&1 || true
}

validate_env

# Check if enddate is close
WARNING_THRESHOLD_DAYS=2
DATE_CHECK=$(remaining_days "$TF_VAR_enddate")
if [ "$DATE_CHECK" -le "0" ]; then
  echo 'ERROR: The expiration date for your environment is either set for today or already in the past.'
  echo '       Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
  abort
elif [ "$DATE_CHECK" -le "$WARNING_THRESHOLD_DAYS" ]; then
  echo -n "WARNING: Your environment will expire in less than $WARNING_THRESHOLD_DAYS days. Do you really want to continue? "
  read CONFIRM
  CONFIRM=$(echo "${CONFIRM}" | tr a-z A-Z)
  if [ "$CONFIRM" != "Y" -a "$CONFIRM" != "YES" ]; then
    echo 'Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
    abort
  fi
fi

# Ensure registration code is chosen
ensure_registration_code

START_TIME=$(date +%s)

mkdir -p "${NAMESPACE_DIR}"

# Perform a quick configuration sanity check before calling Terraform
source $BASE_DIR/resources/common.sh
validate_stack $NAMESPACE $BASE_DIR/resources "${TF_VAR_cdp_license_file:-}"

log "Validate services selection: $CM_SERVICES"
THE_PWD=dummy CLUSTER_HOST=dummy PRIVATE_IP=dummy PUBLIC_DNS=dummy DOCKER_DEVICE=dummy CDSW_DOMAIN=dummy \
IPA_HOST="$([[ $USE_IPA == "yes" ]] && echo dummy || echo "")" USE_IPA="$USE_IPA" \
CLUSTER_ID=dummy PEER_CLUSTER_ID=dummy PEER_PUBLIC_DNS=dummy \
python $BASE_DIR/resources/cm_template.py --cdh-major-version $CDH_MAJOR_VERSION $CM_SERVICES --validate-only

# Presign URLs, if needed
STACK_FILE=$(get_stack_file $NAMESPACE $BASE_DIR/resources exclude-signed)
echo "Using stack: $STACK_FILE"
presign_urls $STACK_FILE

# If EXTRA_CIDR_BLOCKS is defined, merge its content with TF_VAR_extra_cidr_blocks
TF_VAR_extra_cidr_blocks="$(echo "${TF_VAR_extra_cidr_blocks:-},${EXTRA_CIDR_BLOCKS:-}" | sed -E 's#[^0-9.,/]##g;s/,,*/,/g;s/^,//;s/,$//;s/[^,]+/"&"/g;s/^/[/;s/$/]/')"
export TF_VAR_extra_cidr_blocks

log "Check for parcels"
chmod +x $BASE_DIR/resources/check-for-parcels.sh
$BASE_DIR/resources/check-for-parcels.sh

log "Execute pre-launch setup"
pre_launch_setup

log "Ensure key pair exists"
ensure_key_pairs

log "Launching Terraform"
run_terraform apply -auto-approve -parallelism="${TF_VAR_parallelism}" -refresh=true -state=$TF_STATE
refresh_tf_state

log "Monitoring for deployment completion"
"${BASE_DIR}/check-setup-status.sh" "${NAMESPACE}" "${START_TIME}"

log "Deployment completed successfully"

# Clean up
rm -f ${STACK_FILE}.{signed,urls}

echo ""
echo "Instances:"
"${BASE_DIR}/list-details.sh" "${NAMESPACE}"

echo ""
echo "Health checks:"
"${BASE_DIR}/check-services.sh" "${NAMESPACE}"

if [[ ${HAS_CDSW:-0} == 1 && $TF_VAR_deploy_cdsw_model == true ]]; then
  echo "${C_YELLOW}    NOTE: CDSW model is being deployed in the background."
  echo "          Execute the following command later to check on the status of"
  echo "          CDSW and the Model deployment:"
  echo ""
  echo "          ./check-services.sh $NAMESPACE ${C_NORMAL}"
fi

echo ""
echo "Uploading instance details to Web Server:"
"${BASE_DIR}/upload-instance-details.sh" "${NAMESPACE}"

echo ""
echo "Updating registration code:"
"${BASE_DIR}/update-registration-code.sh" "${NAMESPACE}" "$TF_VAR_registration_code"

END_TIME=$(date +%s)
DURATION=$((END_TIME-START_TIME))
log "Deployment completed in $(printf "%d:%02d" "$((DURATION/60))" "$((DURATION%60))") minutes"

) 2>&1 | tee $LOG_NAME
trap - 0
