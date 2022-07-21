#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  exit 1
fi
NAMESPACE=$1

source $BASE_DIR/lib/common.sh

CURL=(curl -s -L -k --connect-timeout 4)

function cleanup() {
  rm -f .curl.*.$$
}

function get_model_status() {
  local ip=$1
  CDSW_API="cdsw.$ip.nip.io/api/v1"
  CDSW_ALTUS_API="cdsw.$ip.nip.io/api/altus-ds-1"
  status=""
  for scheme in http https; do
    token=$(timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-model.$$ --cookie .curl.cj-model.$$ -H 'Content-Type: application/json' --data '{"\""_local"\"":false,"\""login"\"":"\""admin"\"","\""password"\"":"\""${THE_PWD}"\""}' '$scheme://$CDSW_API/authenticate'" 2>/dev/null | jq -r '.auth_token // empty' 2> /dev/null)
    [[ ! -n $token ]] && continue
    status=$(timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-model.$$ --cookie .curl.cj-model.$$ -H 'Content-Type: application/json' -H 'Authorization: Bearer $token' --data '{"\""projectOwnerName"\"":"\""admin"\"","\""latestModelDeployment"\"":true,"\""latestModelBuild"\"":true}' '$scheme://$CDSW_ALTUS_API/models/list-models'" 2>/dev/null | jq -r '.[].latestModelDeployment | select(.model.name == "IoT Prediction Model").status' 2>/dev/null)
    [[ -n $status ]] && break
  done
  echo -n $status
}

function get_viz_status() {
  local ip=$1
  CDSW_API="cdsw.$ip.nip.io/api/v1"
  status=""
  for scheme in http https; do
    token=$(timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-viz.$$ --cookie .curl.cj-viz.$$ -H 'Content-Type: application/json' --data '{"\""_local"\"":false,"\""login"\"":"\""admin"\"","\""password"\"":"\""${THE_PWD}"\""}' '$scheme://$CDSW_API/authenticate'" 2>/dev/null | jq -r '.auth_token // empty' 2> /dev/null)
    [[ ! -n $token ]] && continue
    status=$(timeout 5 "${CURL[*]} -X GET --cookie-jar .curl.cj-viz.$$ --cookie .curl.cj-viz.$$ -H 'Content-Type: application/json' -H 'Authorization: Bearer $token' '$scheme://$CDSW_API/projects/admin/vizapps-workshop/applications'" 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null)
    [[ -n $status ]] && break
  done
  echo -n $status
}

printf "%-40s %-20s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-14s %s\n" "instance" "ip address" "WEB" "CM" "CEM" "NIFI" "NREG" "SREG" "SMM" "HUE" "CDSW" "Model Status" "Viz Status"
ensure_tf_json_file
if [ -s $TF_JSON_FILE ]; then
  (
    web_instance | web_attr long_id public_ip
    cluster_instances | cluster_attr long_id public_ip
  ) | \
  while read instance ip; do
    host="cdp.$ip.nip.io"
    CDSW_API="http://cdsw.$ip.nip.io/api/v1"
    CDSW_ALTUS_API="http://cdsw.$ip.nip.io/api/altus-ds-1"
    (timeout 5 "${CURL[*]} http://$host/api/ping" 2>/dev/null | grep 'Pong!' > /dev/null 2>&1 && echo Ok) > .curl.web.$$ &
    (timeout 5 "${CURL[*]} http://$host:7180/cmf/login" 2>/dev/null | grep "<title>Cloudera Manager</title>" > /dev/null 2>&1 && echo Ok) > .curl.cm.$$ &
    ((timeout 5 "${CURL[*]} http://$host:10088/efm/ui/"        ;  timeout 5 "${CURL[*]} https://$host:10088/efm/ui/")        2>/dev/null | egrep "<title>(CEM|KnoxSSO - Sign In)</title>" > /dev/null 2>&1 && echo Ok) > .curl.cem.$$ &
    ((timeout 5 "${CURL[*]} http://$host:8080/nifi/"           || timeout 5 "${CURL[*]} https://$host:8443/nifi/")           2>/dev/null | grep "<title>NiFi</title>" > /dev/null 2>&1 && echo Ok) > .curl.nifi.$$ &
    ((timeout 5 "${CURL[*]} http://$host:18080/nifi-registry/" || timeout 5 "${CURL[*]} https://$host:18433/nifi-registry/") 2>/dev/null | grep "<title>NiFi Registry</title>" > /dev/null 2>&1 && echo Ok) > .curl.nifireg.$$ &
    ((timeout 5 "${CURL[*]} http://$host:7788/"                || timeout 5 "${CURL[*]} https://$host:7790/")                2>/dev/null | egrep "<title>Schema Registry</title>|Error 401 Authentication required" > /dev/null 2>&1 && echo Ok) > .curl.schreg.$$ &
    ((timeout 5 "${CURL[*]} http://$host:9991/"                || timeout 5 "${CURL[*]} https://$host:9991/")                2>/dev/null | grep "<title>STREAMS MESSAGING MANAGER</title>" > /dev/null 2>&1 && echo Ok) > .curl.smm.$$ &
    ((timeout 5 "${CURL[*]} http://$host:8888/"                ;  timeout 5 "${CURL[*]} https://$host:8889/")                2>/dev/null | grep "<title>Hue" > /dev/null 2>&1 && echo Ok) > .curl.hue.$$ &
    ((timeout 5 "${CURL[*]} http://cdsw.$ip.nip.io/"           || timeout 5 "${CURL[*]} https://cdsw.$ip.nip.io/")           2>/dev/null | egrep "(Cloudera Machine Learning|Cloudera Data Science Workbench)" > /dev/null 2>&1 && echo Ok) > .curl.cml.$$ &
    (get_model_status $ip) > .curl.model.$$ &
    (get_viz_status $ip) > .curl.viz.$$ &
    wait
    printf "%-40s %-20s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-14s %s\n" "$instance" "$ip" "$(cat .curl.web.$$)" "$(cat .curl.cm.$$)" "$(cat .curl.cem.$$)" "$(cat .curl.nifi.$$)" "$(cat .curl.nifireg.$$)" "$(cat .curl.schreg.$$)" "$(cat .curl.smm.$$)" "$(cat .curl.hue.$$)" "$(cat .curl.cml.$$)" "$(cat .curl.model.$$)" "$(cat .curl.viz.$$)"
  done | sort -t\[ -k1,1r -k2,2n
fi
