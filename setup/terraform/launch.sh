#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source ${BASE_DIR}/common.sh

mkdir -p "${BASE_DIR}"/logs
(
set -o errexit
set -o nounset
set -o pipefail

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
validate_env
load_env $NAMESPACE
check_python_modules

# Check if enddate is close
WARNING_THRESHOLD_DAYS=2
DATE_CHECK=$(remaining_days "$TF_VAR_enddate")
if [ "$DATE_CHECK" -le "0" ]; then
  echo 'ERROR: The expiration date for your environment is either set for today or already in the past.'
  echo '       Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
  exit 1
elif [ "$DATE_CHECK" -le "$WARNING_THRESHOLD_DAYS" ]; then
  echo -n "WARNING: Your environment will expire in less than $WARNING_THRESHOLD_DAYS days. Do you really want to continue? "
  read CONFIRM
  CONFIRM=$(echo "${CONFIRM}" | tr a-z A-Z)
  if [ "$CONFIRM" != "Y" -a "$CONFIRM" != "YES" ]; then
    echo 'Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
    exit 1
  fi
fi

START_TIME=$(date +%s)

mkdir -p "${NAMESPACE_DIR}"

# Perform a quick configuration sanity check before calling Terraform
source $BASE_DIR/resources/common.sh
validate_stack $NAMESPACE $BASE_DIR/resources

# Presign URLs, if needed
STACK_FILE=$(get_stack_file $NAMESPACE $BASE_DIR/resources exclude-signed)
echo "Using stack: $STACK_FILE"
presign_urls $STACK_FILE

log "Validate services selection: $CM_SERVICES"
CLUSTER_HOST=dummy PRIVATE_IP=dummy PUBLIC_DNS=dummy DOCKER_DEVICE=dummy CDSW_DOMAIN=dummy \
python $BASE_DIR/resources/cm_template.py --cdh-major-version $CDH_MAJOR_VERSION $CM_SERVICES --validate-only

log "Check for parcels"
chmod +x $BASE_DIR/resources/check-for-parcels.sh
$BASE_DIR/resources/check-for-parcels.sh

log "Ensure key pair exists"
ensure_key_pairs

log "Launching Terraform"
terraform init
# Sets the var below to prevent managed SGs from being added to the SGs we create
if [ -s $NAMESPACE_DIR/terraform.state ]; then
  export TF_VAR_managed_security_group_ids="[$(terraform show -json $NAMESPACE_DIR/terraform.state | \
    jq -r '.values[]?.resources[]? | select(.type == "aws_security_group").values.id | "\"\(.)\""' | \
    tr "\n" "," | sed 's/,$//')]"
fi
terraform apply -auto-approve -parallelism="${TF_VAR_parallelism}" -refresh=true -state=$NAMESPACE_DIR/terraform.state

log "Deployment completed successfully"

echo ""
echo "Instances:"
"${BASE_DIR}/list-details.sh" "${NAMESPACE}"

echo ""
echo "Health checks:"
"${BASE_DIR}/check-services.sh" "${NAMESPACE}"

if [ "$TF_VAR_deploy_cdsw_model" == "true" ]; then
  echo "${C_YELLOW}    NOTE: CDSW model is being deployed in the background."
  echo "          Execute the following command later to check on the status of"
  echo "          CDSW and the Model deployment:"
  echo ""
  echo "          ./check-services.sh $NAMESPACE ${C_NORMAL}"
fi

echo ""
echo "Uploading instance details to Web Server:"
"${BASE_DIR}/upload-instance-details.sh" "${NAMESPACE}"

END_TIME=$(date +%s)
DURATION=$((END_TIME-START_TIME))
log "Deployment completed in $(printf "%d:%02d" "$((DURATION/60))" "$((DURATION%60))") minutes"

) 2>&1 | tee $BASE_DIR/logs/setup.log.${1:-unknown}.$(date +%Y%m%d%H%M%S)
