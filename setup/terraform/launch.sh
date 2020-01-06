#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh
mkdir -p $BASE_DIR/logs
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
load_env $NAMESPACE
check_all_configs
check_python_modules

# Check if enddate is close
WARNING_THRESHOLD_DAYS=2
DATE_CHECK=$(python -c "
from datetime import datetime, timedelta
dt = datetime.now()
dt = dt.replace(hour=0, minute=0, second=0, microsecond=0)
print((datetime.strptime('$TF_VAR_enddate', '%m%d%Y') - dt).days)
")

if [ "$DATE_CHECK" -le "0" ]; then
  echo 'ERROR: The expiration date for your environment is either set for today or already in the past.'
  echo '       Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
  exit 1
elif [ "$DATE_CHECK" -le "$WARNING_THRESHOLD_DAYS" ]; then
  echo -n "WARNING: Your environment will expire in less than $WARNING_THRESHOLD_DAYS days. Do you really want to continue? "
  read CONFIRM
  CONFIRM=$(echo $CONFIRM | tr a-z A-Z)
  if [ "$CONFIRM" != "Y" -a "$CONFIRM" != "YES" ]; then
    echo 'Please update "TF_VAR_endddate" in .env.'"$NAMESPACE"' and try again.'
    exit 1
  fi
fi

mkdir -p $NAMESPACE_DIR

# Perform a quick configuration sanity check before calling Terraform
source $BASE_DIR/resources/common.sh
load_stack $NAMESPACE $BASE_DIR/resources local
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
terraform apply -auto-approve -parallelism=20 -state=$NAMESPACE_DIR/terraform.state

log "Deployment completed successfully"

echo ""
echo "Instances:"
./list-details.sh $NAMESPACE

echo ""
echo "Health checks:"
./check-services.sh $NAMESPACE

if [ "$TF_VAR_deploy_cdsw_model" == "true" ]; then
  echo -e "\033[33m" # set font color to yellow
  echo "    NOTE: CDSW model is being deployed in the background."
  echo "          Execute the following command later to check on the status of"
  echo "          CDSW and the Model deployment:"
  echo ""
  echo "          ./check-services.sh $NAMESPACE"
  echo -e -n "\033[0m" # back to normal color
fi

echo ""
echo "Uploading instance details to Web Server:"
./upload-instance-details.sh $NAMESPACE

) 2>&1 | tee $BASE_DIR/logs/setup.log.${1:-unknown}.$(date +%Y%m%d%H%M%S)
