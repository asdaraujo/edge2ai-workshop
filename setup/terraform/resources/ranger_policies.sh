#!/bin/bash
set -e
set -u

ENABLE_TLS=$1

CURL=(curl -Lsku admin:${THE_PWD} -H "Accept: application/json" -H "Content-Type: application/json")

if [[ $ENABLE_TLS == "yes" ]]; then
  HTTP_SCHEME="https"
  NIFI_PORT="8443"
  RANGER_PORT="6182"
else
  HTTP_SCHEME="http"
  NIFI_PORT="8080"
  RANGER_PORT="6080"
fi

RANGER_API_URL="${HTTP_SCHEME}://$(hostname -f):${RANGER_PORT}/service"
NIFI_API_URL="${HTTP_SCHEME}://$(hostname -f):${NIFI_PORT}/nifi-api"

NIFI_SERVICE="OneNodeCluster_nifi"
NIFI_REGISTRY_SERVICE="OneNodeCluster_nifiregistry"
KUDU_SERVICE="cm_kudu"
KAFKA_SERVICE="cm_kafka"
HDFS_SERVICE="cm_hdfs"
SCHEMA_REGISTRY_SERVICE="cm_schema-registry"

function create_user() {
  local username=$1
  echo -n "Creating user [$username] - "
  local ret=$("${CURL[@]}" \
    -s -w "%{http_code}" -o /dev/null \
    -X POST "$RANGER_API_URL/xusers/secure/users" \
    -i -d '
{
  "groupIdList":null,
  "status":1,
  "userRoleList":["ROLE_USER"],
  "name":"'"$username"'",
  "password":"'"$THE_PWD"'",
  "firstName":"'"$username"'",
  "lastName":"'"$username"'",
  "emailAddress":""
}
')
  echo "Return code: $ret"
}

function create_policy() {
  local service_name=$1
  local service_type=$2
  local policy_name=$3
  shift 3
  echo -n "Creating policy [$policy_name] for service [$service_name] - "
  local ret=$("${CURL[@]}" \
    -s -w "%{http_code}" -o /dev/null \
    -X POST "$RANGER_API_URL/public/v2/api/policy" \
    -d '
{
  "isEnabled": true,
  "version": 1,
  "service": "'"$service_name"'",
  "name": "'"$policy_name"'",
  "policyType": 0,
  "policyPriority": 0,
  "description": "'"$policy_name"'",
  "isAuditEnabled": true,
  "resources": {
'"$(
    first=1
    while [[ $# -gt 0 ]]; do
      resource=$1
      values=$(echo "$2" | sed 's/[^;][^;]*/"&"/g;s/;/,/g')
      shift 2
      if [[ first -eq 0 ]]; then
        echo ","
      fi
      echo -n '    "'"$resource"'": {
      "values": ['"$values"'],
      "isExcludes": false,
      "isRecursive": false
    }'
      first=0
    done
    echo "")"'
  },
  "policyItems": [],
  "denyPolicyItems": [],
  "allowExceptions": [],
  "denyExceptions": [],
  "dataMaskPolicyItems": [],
  "rowFilterPolicyItems": [],
  "serviceType": "'"$service_type"'",
  "options": {},
  "validitySchedules": [],
  "policyLabels": [],
  "zoneName": "",
  "isDenyAllElse": false
}'
)
  echo "Return code: $ret"
}

function get_policies() {
  local service_name=${1:-$NIFI_SERVICE}
  "${CURL[@]}" \
    -X GET "$RANGER_API_URL/public/v2/api/service/${service_name}/policy"
}

function get_policy() {
  local policy_name=$1
  local perms=${2:-}
  local service_name=${3:-$NIFI_SERVICE}
  local policy=$(get_policies "$service_name" | jq -r '.[] | select(.name == "'"$policy_name"'")')
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
  local service_name=${2:-$NIFI_SERVICE}
  get_policy "$policy_name" "" "$service_name" | jq -r '.id'
}

function add_perms_to_policy() {
  local perms=$1
  local policy_name=$2
  local service_name=${3:-$NIFI_SERVICE}
  echo -n "Adding permissions [$perms] to policy [$policy_name] or service [$service_name] - "
  local ret=$("${CURL[@]}" \
    -s -w "%{http_code}" -o /dev/null \
    -X PUT "$RANGER_API_URL/public/v2/api/policy/$(get_policy_id "$policy_name" "$service_name")" \
    -d @<(get_policy "$policy_name" "$perms" "$service_name")
  )
  echo "Return code: $ret"
}

function get_root_pg {
  local token=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" -d "username=admin&password=${THE_PWD}" -k "$NIFI_API_URL/access/token" 2>/dev/null)
  local retries=120
  while [[ $retries -gt 0 ]]; do
    local root_pg_id=$(curl -H "Authorization: Bearer $token" -k "$NIFI_API_URL/flow/process-groups/root" 2> /dev/null | jq -r '.processGroupFlow.id' 2>/dev/null)
    if [[ "$root_pg_id" != "" ]]; then
      echo "$root_pg_id"
      return
    fi
    retries=$((retries - 1 ))
    echo "Waiting to get Root PG id (retries left: $retries)" >&2
    sleep 1
  done
  echo "Failed to get root PG id"
}

# Create host user
create_user "$(hostname -f)"

# NiFi

create_policy "$NIFI_SERVICE" "nifi" "Data Access" "nifi-resource" "/data/*"
create_policy "$NIFI_SERVICE" "nifi" "Provenance"  "nifi-resource" "/provenance;/provenance-data/*/*"
create_policy "$NIFI_SERVICE" "nifi" "System"      "nifi-resource" "/system"
add_perms_to_policy ":cdp-admins;cdp-users:READ;WRITE" "Flow"
add_perms_to_policy ":cdp-admins:READ;WRITE"       "Restricted Components"
add_perms_to_policy ":cdp-admins:READ;WRITE"       "Controller"
add_perms_to_policy ":cdp-admins:READ;WRITE"       "Policies"
add_perms_to_policy ":cdp-admins:READ;WRITE"       "Tenants"
add_perms_to_policy ":cdp-admins;nifi;cdp-users:READ;WRITE" "Data Access"
add_perms_to_policy ":cdp-admins;nifi;cdp-users:READ;WRITE" "Provenance"
add_perms_to_policy ":cdp-admins;nifi:READ"             "System"
ROOT_PG_ID=$(get_root_pg)
if [[ $ROOT_PG_ID != "" ]]; then
  create_policy "$NIFI_SERVICE" "nifi" "Root Process Group" "nifi-resource" "/process-groups/$ROOT_PG_ID"
  add_perms_to_policy ":cdp-admins;nifi;cdp-users:READ;WRITE" "Root Process Group"
fi

## Needed for EFM to send data via S2S
create_policy "$NIFI_SERVICE" "nifi" "Site-To-Site" "nifi-resource" "/site-to-site"
create_policy "$NIFI_SERVICE" "nifi" "Input ports"  "nifi-resource" "/data-transfer/input-ports/*"
create_policy "$NIFI_SERVICE" "nifi" "Output ports" "nifi-resource" "/data-transfer/output-ports/*"
add_perms_to_policy "$(hostname -f):nifi:READ"  "Site-To-Site"
add_perms_to_policy "$(hostname -f):nifi:WRITE" "Input ports"
add_perms_to_policy "$(hostname -f):nifi:WRITE" "Output ports"

# Kafka

add_perms_to_policy ":cdp-admins:consume;describe;delete"                                                                                    "all - consumergroup"   "$KAFKA_SERVICE"
add_perms_to_policy ":cdp-admins:publish;consume;configure;describe;create;delete;describe_configs;alter_configs;alter"                      "all - topic"           "$KAFKA_SERVICE"
add_perms_to_policy ":cdp-admins:publish;describe"                                                                                           "all - transactionalid" "$KAFKA_SERVICE"
add_perms_to_policy ":cdp-admins:configure;describe;kafka_admin;create;idempotent_write;describe_configs;alter_configs;cluster_action;alter" "all - cluster"         "$KAFKA_SERVICE"
add_perms_to_policy ":cdp-admins:describe"                                                                                                   "all - delegationtoken" "$KAFKA_SERVICE"
add_perms_to_policy ":cdp-admins:publish"                                                                                                    "ATLAS_HOOK"            "$KAFKA_SERVICE"
# TODO: The ssb permissions below are only necessary until CSA-1470 is resolved
add_perms_to_policy "ssb::consume;describe"                                                                                              "all - consumergroup"   "$KAFKA_SERVICE"
add_perms_to_policy "ssb::consume;describe"                                                                                              "all - topic"           "$KAFKA_SERVICE"

# HDFS

add_perms_to_policy ":cdp-admins:read;write;execute" "all - path" "$HDFS_SERVICE"

# Schema Registry

create_policy "$SCHEMA_REGISTRY_SERVICE" "schema-registry" "all - serde"                                                        "serde" "*"
create_policy "$SCHEMA_REGISTRY_SERVICE" "schema-registry" "all - schema-group, schema-metadata"                                "schema-metadata" "*" "schema-group" "*"
create_policy "$SCHEMA_REGISTRY_SERVICE" "schema-registry" "all - schema-group, schema-metadata, schema-branch"                 "schema-metadata" "*" "schema-group" "*" "schema-branch" "*"
create_policy "$SCHEMA_REGISTRY_SERVICE" "schema-registry" "all - registry-service"                                             "registry-service" "*"
create_policy "$SCHEMA_REGISTRY_SERVICE" "schema-registry" "all - schema-group, schema-metadata, schema-branch, schema-version" "schema-metadata" "*" "schema-group" "*" "schema-branch" "*" "schema-version" "*"
add_perms_to_policy ":cdp-admins:create;read;update;delete" "all - serde"                                                        "$SCHEMA_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:create;read;update;delete" "all - schema-group, schema-metadata"                                "$SCHEMA_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:create;read;update;delete" "all - schema-group, schema-metadata, schema-branch"                 "$SCHEMA_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:create;read;update;delete" "all - registry-service"                                             "$SCHEMA_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:create;read;update;delete" "all - schema-group, schema-metadata, schema-branch, schema-version" "$SCHEMA_REGISTRY_SERVICE"
# CDP 7.1.4 and earlier had a predefined policy called "Add super used" for the registry-service resource. The one below is for "backward compatibility".
add_perms_to_policy ":cdp-admins:create;read;update;delete" "Add super user"                                                     "$SCHEMA_REGISTRY_SERVICE"

# NiFi Registry

add_perms_to_policy ":cdp-admins:READ;WRITE;DELETE" "Actuator" "$NIFI_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:READ;WRITE;DELETE" "Buckets"  "$NIFI_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:READ"              "Tenants"  "$NIFI_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:READ"              "Policies" "$NIFI_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:READ;WRITE;DELETE" "Swagger"  "$NIFI_REGISTRY_SERVICE"
add_perms_to_policy ":cdp-admins:READ;WRITE;DELETE" "Proxies"  "$NIFI_REGISTRY_SERVICE"

# Kudu

create_policy "$KUDU_SERVICE" "kudu" "All databases" "database" "*" "table" "*" "column" "*"
add_perms_to_policy ":cdp-admins:all;alter;create;delete;drop;insert;metadata;select;update" "All databases" "$KUDU_SERVICE"
