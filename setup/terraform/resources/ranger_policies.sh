#!/bin/bash
set -e
set -u

CURL=(curl -Lsku admin:${THE_PWD} -H "Accept: application/json" -H "Content-Type: application/json")
RANGER_API_URL="https://$(hostname -f):6182/service"
NIFI_API_URL="https://$(hostname -f):8443/nifi-api"

function create_policy() {
  local policy_name=$1
  local resources=$2
  resources=$(echo "$resources" | sed 's/[^;][^;]*/"&"/g;s/;/,/g')
  "${CURL[@]}" \
    -X POST "$RANGER_API_URL/public/v2/api/policy" \
    --output /dev/null \
    -d '
{
  "isEnabled": true,
  "version": 1,
  "service": "OneNodeCluster_nifi",
  "name": "'"$policy_name"'",
  "policyType": 0,
  "policyPriority": 0,
  "description": "'"$policy_name"'",
  "isAuditEnabled": true,
  "resources": {
    "nifi-resource": {
      "values": ['"$resources"'],
      "isExcludes": false,
      "isRecursive": false
    }
  },
  "policyItems": [],
  "denyPolicyItems": [],
  "allowExceptions": [],
  "denyExceptions": [],
  "dataMaskPolicyItems": [],
  "rowFilterPolicyItems": [],
  "serviceType": "nifi",
  "options": {},
  "validitySchedules": [],
  "policyLabels": [],
  "zoneName": "",
  "isDenyAllElse": false
}'
}

function get_policies() {
  "${CURL[@]}" \
    -X GET "$RANGER_API_URL/public/v2/api/service/OneNodeCluster_nifi/policy"
}

function get_policy() {
  local policy_name=$1
  local perms=${2:-}
  local policy=$(get_policies | jq -r '.[] | select(.name == "'"$policy_name"'")')
  if [ "$perms" == "" ]; then
    echo "$policy"
  else
    local users=$(echo "${perms%%:*}" | sed 's/[^;][^;]*/"&"/g;s/;/,/g')
    local groups=$(echo "$perms" | sed 's/^[^:]*://;s/:[^:]*$//;s/[^;][^;]*/"&"/g;s/;/,/g')
    local accesses=$(echo "${perms##*:}" | sed 's/[^;][^;]*/{"type":"&","isAllowed":true}/g;s/;/,/g')
    echo "$policy" | jq -r '.policyItems|=.+[{"users":['"$users"'],"groups":['"$groups"'],"accesses":['"$accesses"']}]'
  fi
}

function get_policy_id() {
  local policy_name=$1
  get_policy "$policy_name" | jq -r '.id'
}

function add_perms_to_policy() {
  local perms=$1
  local policy_name=$2
  "${CURL[@]}" \
    -X PUT "$RANGER_API_URL/public/v2/api/policy/$(get_policy_id "$policy_name")" \
    --output /dev/null \
    -d @<(get_policy "$policy_name" "$perms")
}

function get_root_pg {
  local token=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" -d 'username=admin&password=${THE_PWD}' -k "$NIFI_API_URL/access/token" 2>/dev/null)
  local retries=120
  while [[ $retries -gt 0 ]]; do
    local root_pg_id=$(curl -H "Authorization: Bearer $token" -k "$NIFI_API_URL/flow/process-groups/root" 2> /dev/null | jq -r '.processGroupFlow.id' 2>/dev/null)
    if [[ "$root_pg_id" != "" ]]; then
      echo "$root_pg_id"
      return
    fi
    echo "Waiting to get Root PG id" >&2
    sleep 1
    retries=$((retries - 1 ))
  done
}

add_perms_to_policy ":admins;users:READ;WRITE" "Flow"
add_perms_to_policy ":admins:READ;WRITE" "Restricted Components"
add_perms_to_policy ":admins:READ;WRITE" "Controller"
add_perms_to_policy ":admins:READ;WRITE" "Policies"
add_perms_to_policy ":admins:READ;WRITE" "Tenants"
create_policy "Data Access" "/data/*"
add_perms_to_policy ":admins;users:READ;WRITE" "Data Access"
create_policy "Provenance" "/provenance;/provenance-data/*/*"
add_perms_to_policy ":admins;users:READ;WRITE" "Provenance"
ROOT_PG_ID=$(get_root_pg)
if [[ $ROOT_PG_ID != "" ]]; then
  create_policy "Root Process Group" "/process-groups/$ROOT_PG_ID"
  add_perms_to_policy ":admins;users:READ;WRITE" "Root Process Group"
fi
