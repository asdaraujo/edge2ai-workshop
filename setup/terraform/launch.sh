#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
mkdir -p $BASE_DIR/logs
(
set -o errexit
set -o nounset
set -o pipefail

for sig in {0..31}; do
  trap 'RET=$?; if [ $RET != 0 ]; then echo -e "\n   SETUP FAILED!!! (signal: '$sig', exit code: $RET)\n"; fi' $sig
done

source $BASE_DIR/.env
source $BASE_DIR/common.sh

# Check for parcels
chmod +x $BASE_DIR/resources/check-for-parcels.sh
$BASE_DIR/resources/check-for-parcels.sh

ensure_key_pair

log "Launching Terraform"
terraform init
terraform apply -auto-approve -parallelism=20

log "Deployment completed successfully"

echo ""
echo "Instances:"
./list-details.sh

echo ""
echo "Health checks:"
./check-services.sh

) 2>&1 | tee $BASE_DIR/logs/setup.log.$(date +%Y%m%d%H%M%S)
