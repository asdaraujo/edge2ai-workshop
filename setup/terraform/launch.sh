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

for sig in {0..31}; do
  trap 'RET=$?; if [ $RET != 0 ]; then echo -e "\n   SETUP FAILED!!! (signal: '$sig', exit code: $RET)\n"; fi' $sig
done

mkdir -p $NAMESPACE_DIR

# Check for parcels
chmod +x $BASE_DIR/resources/check-for-parcels.sh
$BASE_DIR/resources/check-for-parcels.sh

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

echo ""
echo "Uploading instance details to Web Server:"
./upload-instance-details.sh $NAMESPACE

) 2>&1 | tee $BASE_DIR/logs/setup.log.$(date +%Y%m%d%H%M%S)
