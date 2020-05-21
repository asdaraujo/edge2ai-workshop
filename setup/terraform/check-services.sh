#!/bin/bash
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

trap "rm -f .cml .cem .cj .cm .hue .model .nifi .nifireg .schreg .smm .web" 0

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

printf "%-30s %-30s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %s\n" "instance" "ip address" "WEB" "CM" "CEM" "NIFI" "NREG" "SREG" "SMM" "HUE" "CDSW" "Model Status"
(cd $BASE_DIR && terraform show -json $NAMESPACE_DIR/terraform.state) | \
jq -r '.values.root_module.resources[] | select(.address == "aws_instance.web" or .address == "aws_instance.cluster") | "\(.address)[\(.index)] \(.values.public_ip) \(.values.public_dns)"' | \
while read instance ip host; do
  CDSW_API="http://cdsw.$ip.nip.io/api/v1"
  CDSW_ALTUS_API="http://cdsw.$ip.nip.io/api/altus-ds-1"
  (curl -L http://$host/api/ping 2>/dev/null | grep 'Pong!' > /dev/null 2>&1 && echo Ok) > .web &
  (curl -k -L http://$host:7180/cmf/login 2>/dev/null | grep "<title>Cloudera Manager</title>" > /dev/null 2>&1 && echo Ok) > .cm &
  ((curl -L http://$host:10080/efm/ui/        || curl -k -L https://$host:10080/efm/ui/)        2>/dev/null | grep "<title>CEM</title>" > /dev/null 2>&1 && echo Ok) > .cem &
  ((curl -L http://$host:8080/nifi/           || curl -k -L https://$host:8443/nifi/)           2>/dev/null | grep "<title>NiFi</title>" > /dev/null 2>&1 && echo Ok) > .nifi &
  ((curl -L http://$host:18080/nifi-registry/ || curl -k -L https://$host:18433/nifi-registry/) 2>/dev/null | grep "<title>NiFi Registry</title>" > /dev/null 2>&1 && echo Ok) > .nifireg &
  ((curl -L http://$host:7788/                || curl -k -L https://$host:7790/)                2>/dev/null | egrep "<title>Schema Registry</title>|Error 401 Authentication required" > /dev/null 2>&1 && echo Ok) > .schreg &
  ((curl -L http://$host:9991/                || curl -k -L https://$host:9991/)                2>/dev/null | grep "<title>STREAMS MESSAGING MANAGER</title>" > /dev/null 2>&1 && echo Ok) > .smm &
  ((curl -L http://$host:8888/                ;  curl -k -L https://$host:8889/)                2>/dev/null | grep "<title>Hue" > /dev/null 2>&1 && echo Ok) > .hue &
  ((curl -L http://cdsw.$ip.nip.io/           || curl -k -L https://cdsw.$ip.nip.io/)           2>/dev/null | egrep "<title.*(Cloudera Machine Learning|Cloudera Data Science Workbench)" > /dev/null 2>&1 && echo Ok) > .cml &
  (token=$(curl -X POST --cookie-jar .cj --cookie .cj -H "Content-Type: application/json" --data '{"_local":false,"login":"admin","password":"supersecret1"}' "$CDSW_API/authenticate" 2>/dev/null | jq -r '.auth_token' 2> /dev/null) && \
   curl -X POST --cookie-jar .cj --cookie .cj -H "Content-Type: application/json" -H "Authorization: Bearer $token" --data '{"projectOwnerName":"admin","latestModelDeployment":true,"latestModelBuild":true}' "$CDSW_ALTUS_API/models/list-models" 2>/dev/null | jq -r '.[].latestModelDeployment | select(.model.name == "IoT Prediction Model").status' 2>/dev/null) > .model &
  wait
  printf "%-30s %-30s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %s\n" "$instance" "$ip" "$(cat .web)" "$(cat .cm)" "$(cat .cem)" "$(cat .nifi)" "$(cat .nifireg)" "$(cat .schreg)" "$(cat .smm)" "$(cat .hue)" "$(cat .cml)" "$(cat .model)"
done | sort -t\[ -k1,1r -k2,2n
