#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [[ $# -ne 1 && ! ($# -eq 2 && $2 == "--compact") ]]; then
  echo "Syntax: $0 <namespace> [--compact]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
COMPACT=${2:-}

source $BASE_DIR/lib/common.sh

CURL=(curl -s -L -k --connect-timeout 4)

function cleanup() {
  rm -f .curl.*.$$
}

function get_model_status() {
  local cdsw_api_url=$1
  local cdsw_altus_api_url=$2
  token=$(timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-model.$$ --cookie .curl.cj-model.$$ -H 'Content-Type: application/json' --data '{"\""_local"\"":false,"\""login"\"":"\""admin"\"","\""password"\"":"\""${THE_PWD}"\""}' '${cdsw_api_url}/authenticate'" 2>/dev/null | jq -r '.auth_token // empty' 2> /dev/null)
  [[ ! -n $token ]] && return
  timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-model.$$ --cookie .curl.cj-model.$$ -H 'Content-Type: application/json' -H 'Authorization: Bearer $token' --data '{"\""projectOwnerName"\"":"\""admin"\"","\""latestModelDeployment"\"":true,"\""latestModelBuild"\"":true}' '${cdsw_altus_api_url}/models/list-models'" 2>/dev/null | jq -r '.[].latestModelDeployment | select(.model.name == "IoT Prediction Model").status' 2>/dev/null
}

function get_viz_status() {
  local cdsw_api_url=$1
  token=$(timeout 5 "${CURL[*]} -X POST --cookie-jar .curl.cj-viz.$$ --cookie .curl.cj-viz.$$ -H 'Content-Type: application/json' --data '{"\""_local"\"":false,"\""login"\"":"\""admin"\"","\""password"\"":"\""${THE_PWD}"\""}' '${cdsw_api_url}/authenticate'" 2>/dev/null | jq -r '.auth_token // empty' 2> /dev/null)
  [[ ! -n $token ]] && return
  timeout 5 "${CURL[*]} -X GET --cookie-jar .curl.cj-viz.$$ --cookie .curl.cj-viz.$$ -H 'Content-Type: application/json' -H 'Authorization: Bearer $token' '${cdsw_api_url}/projects/admin/vizapps-workshop/applications'" 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null
}

function check_url() {
  local url_template=$1
  local ip=$2
  local ok_pattern=$3
  timeout 5 "${CURL[*]} $(url_for_ip "$url_template" "$ip")" 2>/dev/null | egrep "$ok_pattern" > /dev/null 2>&1 && echo Ok
}

# need to load the stack for calling get_service_urls
source $BASE_DIR/resources/common.sh
validate_stack $NAMESPACE $BASE_DIR/resources "$(get_license_file_path)"

SERVICE_URLS=$(get_service_urls)
WEB_URL='http://{host}/api/ping'
CM_URL=$(echo "$SERVICE_URLS" | service_url CM)
EFM_URL=$(echo "$SERVICE_URLS" | service_url EFM)
NIFI_URL=$(echo "$SERVICE_URLS" | service_url NIFI)
NREG_URL=$(echo "$SERVICE_URLS" | service_url NIFIREG)
SREG_URL=$(echo "$SERVICE_URLS" | service_url SR)
SMM_URL=$(echo "$SERVICE_URLS" | service_url SMM)
HUE_URL=$(echo "$SERVICE_URLS" | service_url HUE)
SSB_URL=$(echo "$SERVICE_URLS" | service_url SSB)
CDSW_URL=$(echo "$SERVICE_URLS" | service_url CDSW)

CDSW_API_URL="${CDSW_URL%/}/api/v1"
CDSW_ALTUS_API_URL="${CDSW_URL%/}/api/altus-ds-1"

if [[ $COMPACT == "--compact" ]]; then
  FORMAT="%s %s %s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n"
else
  FORMAT="%-40s %-20s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-14s %s\n"
fi

printf "$FORMAT" "instance" "ip address" "WEB" "CM" "EFM" "NIFI" "NREG" "SREG" "SMM" "HUE" "SSB" "CDSW" "Model Status" "Viz Status"
ensure_tf_json_file
if [ -s $TF_JSON_FILE ]; then
  (
    web_instance | web_attr long_id public_ip
    cluster_instances | cluster_attr long_id public_ip
  ) | \
  while read instance ip; do
    check_url "$WEB_URL"           $ip 'Pong!' > .curl.web.$$ &
    check_url "${CM_URL}cmf/login" $ip "<title>Cloudera Manager</title>" > .curl.cm.$$ &
    check_url "$EFM_URL"           $ip "<title>(CEM|KnoxSSO - Sign In)</title>" > .curl.cem.$$ &
    check_url "$NIFI_URL"          $ip "<title>NiFi</title>" > .curl.nifi.$$ &
    check_url "$NREG_URL"          $ip "<title>NiFi Registry</title>" > .curl.nifireg.$$ &
    check_url "$SREG_URL"          $ip "<title>Schema Registry</title>|Error 401 Authentication required" > .curl.schreg.$$ &
    check_url "$SMM_URL"           $ip "<title>STREAMS MESSAGING MANAGER</title>" > .curl.smm.$$ &
    check_url "$HUE_URL"           $ip "<title>Hue" > .curl.hue.$$ &
    check_url "$SSB_URL"           $ip "<title>Streaming SQL Console" > .curl.ssb.$$ &
    check_url "$CDSW_URL"          $ip "(Cloudera Machine Learning|Cloudera Data Science Workbench)" > .curl.cdsw.$$ &
    cdsw_api_url=$(url_for_ip "$CDSW_API_URL" $ip)
    cdsw_altus_api_url=$(url_for_ip "$CDSW_ALTUS_API_URL" $ip)
    (get_model_status $cdsw_api_url $cdsw_altus_api_url) > .curl.model.$$ &
    (get_viz_status $cdsw_api_url) > .curl.viz.$$ &
    wait
    printf "$FORMAT" "$instance" "$ip" \
      "$(cat .curl.web.$$)" "$(cat .curl.cm.$$)" "$(cat .curl.cem.$$)" "$(cat .curl.nifi.$$)" \
      "$(cat .curl.nifireg.$$)" "$(cat .curl.schreg.$$)" "$(cat .curl.smm.$$)" "$(cat .curl.hue.$$)" \
      "$(cat .curl.ssb.$$)" "$(cat .curl.cdsw.$$)" "$(cat .curl.model.$$)" "$(cat .curl.viz.$$)"
  done | sort -t\[ -k1,1r -k2,2n
fi
