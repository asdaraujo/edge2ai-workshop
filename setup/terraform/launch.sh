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

# Load bootstrap scripts to the resource directory
chmod +x $BASE_DIR/resources/check-for-parcels.sh
$BASE_DIR/resources/check-for-parcels.sh
#rm -rf $BASE_DIR/resources
#mkdir -p $BASE_DIR/resources
#find $BASE_DIR/.. -maxdepth 1 -type f -exec cp -f {} $BASE_DIR/resources/ \;
#cp -r $BASE_DIR/../parcels $BASE_DIR/../csds $BASE_DIR/resources/

ensure_key_pair

log "Launching Terraform"
terraform apply -auto-approve

PUBLIC_CIDRS=$(terraform show -json | jq -r '.values[].resources[] | select(.type == "aws_instance") | "\"\(.values.public_ip)/32\""' | tr "\n" "," | sed 's/,$//')
SG_ID=$(terraform state show aws_security_group.bootcamp_sg -no-color | grep "^ *id " | sed 's/.* = //;s/"//g')
cat > rules.tf <<EOF
resource "aws_security_group_rule" "allow_cdsw_healthcheck" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [$PUBLIC_CIDRS]
  security_group_id = "$SG_ID"
}
EOF
terraform apply -auto-approve

log "Deployment completed successfully"
echo ""
./list-details.sh
) 2>&1 | tee $BASE_DIR/logs/setup.log.$(date +%Y%m%d%H%M%S)
