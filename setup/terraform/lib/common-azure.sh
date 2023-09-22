#!/bin/bash

AVAILABLE_SCRIPTS=(
  launch
  terminate
  list-details
  check-services
  check-setup-status
  connect-to-cluster
  browse-cluster
  browse-cluster-socks
  close-registration
  manage-instances
  manage-ip
  open-registration
  rsync-resources
  run-on-all-clusters
  run-on-cluster
  start-instances
  stop-instances
  sync-ip-addresses
  update-registration-code
  upload-instance-details
  #
  test
  launch2
  tf-admin
)

AZURE_PRICES_URL_TEMPLATE='https://prices.azure.com/api/retail/prices?$filter=serviceName%20eq%20%27Virtual%20Machines%27and%20armRegionName%20eq%20%27REGION%27%20and%20armSkuName%20eq%20%27INSTANCE_TYPE%27'

function get_instance_hourly_cost() {
  local instance_type=$1
  local prices_url=$(echo "$AZURE_PRICES_URL_TEMPLATE" | sed "s/REGION/$TF_VAR_azure_region/;s/INSTANCE_TYPE/$instance_type/")
  local tmp_file=/tmp/instance-cost.$$
  local ret=$(curl -w "%{http_code}" "$prices_url" -o $tmp_file --stderr /dev/null)
  if [[ $ret == 200 ]]; then
    jq -r '.Items[] | select(.type == "Consumption" and .unitOfMeasure == "1 Hour" and (.skuName | contains("Spot") | not) and (.skuName | contains("Low Priority") | not) and (.productName | contains("Windows") | not)) | "\(.effectiveStartDate) \(.retailPrice)"' $tmp_file | sort | tail -1 | awk '{print $2}'
  fi
  rm -f $tmp_file
}

function validate_cloud_parameters() {
  if [[ ${TF_VAR_azure_region:-} == "" || ${TF_VAR_azure_subscription_id:-} == "" || ${TF_VAR_azure_tenant_id:-} == "" ]]; then
    echo "${C_RED}ERROR: The following properties must be set in the .env.${NAMESPACE} file:"
    echo "         - TF_VAR_azure_region"
    echo "         - TF_VAR_azure_subscription_id"
    echo "         - TF_VAR_azure_tenant_id"
    echo "${C_NORMAL}"
    exit 1
  fi
}

function is_cli_available() {
  [[ $(get_cli_version) == "2"* ]] && echo yes || echo no
}

function get_cli_version() {
  az version 2>/dev/null | jq -r '.["azure-cli"]' || true
}

function get_cloud_account_info() {
  az account show
}

function cloud_login() {
  az login
}

function list_cloud_instances() {
  local instance_ids=$1
  # Returns: id, state, name, owner, enddate
  # Order by: state
  local rg=$(get_resource_attr azurerm_resource_group rg name)
  local filter=$(python -c 'import sys;print(",".join(['\''"{}"'\''.format(x.lower()) for x in sys.argv[1:]]))' $instance_ids)
  az vm list --resource-group "$rg" -d | jq -r '.[] | select(([.id | ascii_downcase] - ['"$filter"'] | length) == 0) | "\(.powerState | gsub(" "; "") | gsub("VM"; "")) \(.tags.owner) \(.tags.enddate) \(.name) \(.id)"' | sort -k2
}

function security_groups() {
  local sg_type=$1
  get_resource_attr azurerm_network_security_group "workshop_${sg_type}_sg" id
}

function start_instances() {
  local instance_ids=$1
  az vm start --ids $instance_ids
}

function stop_instances() {
  local instance_ids=$1
  az vm deallocate --ids $instance_ids
}

function terminate_instances() {
  local instance_ids=$1
  az vm delete --ids $instance_ids
}

function describe_instances() {
  local instance_ids=$1
  az vm show --ids $instance_ids | yamlize
}

function set_instances_tag() {
  local instance_ids=$1
  local tag=$2
  local value=$3
  az vm update --ids $instance_ids --set "tags.${tag}=${value}" | yamlize
}

function is_instance_protected() {
  local instance_id=$1
  local cnt=$(az resource lock list --resource "$instance_id" | jq 'map(select(.level == "CanNotDelete")) | length')
  [[ $cnt -eq 0 ]] && echo false || echo true
}

function protect_instance() {
  local instance_id=$1
  az resource lock create --resource "$instance_id" --name "$(echo "$instance_id" | sed 's#/#_#g')" --lock-type CanNotDelete
}

function unprotect_instance() {
  local instance_id=$1
  az resource lock delete --resource "$instance_id" --name "$(echo "$instance_id" | sed 's#/#_#g')"
}

function pre_launch_setup() {
  # noop
  true
}

function get_ingress() {
  # Return the matched ingress rule. One rule per line with the following format: cidr protocol port
  local sg_id=$1
  local cidr=${2:-}
  local protocol=${3:-}
  local port=${4:-}
  local description=${5:-}
  local cidr_filter=""
  local protocol_filter=""
  local port_filter=""
  local description_filter=""
  if [[ $cidr != "" ]]; then
    cidr_filter='select(.source_address_prefix == "'"$cidr"'") |'
  fi
  if [[ $protocol != "" ]]; then
    if [[ $protocol == "all" ]]; then
      protocol="*"
    fi
    protocol_filter='select(.protocol == "'"$protocol"'") |'
  fi
  if [[ $port != "" ]]; then
    port_filter='select(.destination_port_range == "'"$port"'") |'
  fi
  if [[ $description != "" ]]; then
    description_filter='select(.description == "'"$description"'") |'
  fi
  ensure_tf_json_file
  jq -r '.values.root_module.resources[]?.values | select(.id == "'"$sg_id"'").security_rule[]? | select(.direction == "Inbound") | '"$protocol_filter"' '"$port_filter"' '"$description_filter"' '"$cidr_filter"' "\(.source_address_prefix) \(if .protocol == "*" then "all" else .protocol end) \(.destination_port_range)"' $TF_JSON_FILE
}

function add_sec_group_ingress_rule() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}
  local description=${5:-default}

  local rule_name="${cidr//[^[0-9]/_}_${protocol}_${port}"
  local rg=$(get_resource_attr azurerm_resource_group rg name)
  local sg=$(get_resource_attr azurerm_network_security_group '.values.id == "'"$group_id"'"' name)
  local tmp_file=/tmp/add-ingress.$$

  [[ $protocol == "all" ]] && actual_protocol="*" || actual_protocol="$protocol"
  [[ $port == "all" ]] && actual_port="*" || actual_port="$port"

  while true; do
    local priority=$(date +%s)
    priority=$(( (priority % 3995) + 101 ))
    set +e
    az network nsg rule create \
      --name "${rule_name}" \
      --nsg-name "$sg" \
      --priority "$priority" \
      --resource-group "$rg" \
      --access Allow \
      --description "$description" \
      --destination-port-ranges "$actual_port" \
      --direction Inbound \
      --protocol "$actual_protocol" \
      --source-address-prefixes "$cidr" > $tmp_file 2>&1
    local ret=$?
    if [[ $ret -eq 0 ]]; then
      echo "  Granted access on ${group_id}, protocol=${protocol}, port=${port} to ${cidr} $([[ $description == "" ]] || echo "($description)") $([[ $force == "force" ]] && echo " - (forced)" || true)"
      break
    elif [[ $ret -ne 0 && $(grep -c "Rules cannot have the same Priority and Direction" $tmp_file) -eq 0 ]]; then
      cat $tmp_file
      rm -f $tmp_file
      exit $ret
    fi
    rm -f $tmp_file
    set -e
  done
}

function remove_sec_group_ingress_rule() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}

  local rule_name="${cidr//[^[0-9]/_}_${protocol}_${port}"
  local rg=$(get_resource_attr azurerm_resource_group rg name)
  local sg=$(get_resource_attr azurerm_network_security_group '.values.id == "'"$group_id"'"' name)
  local tmp_file=/tmp/remove-ingress.$$

  set +e
  az network nsg rule delete \
    --name "${rule_name}" \
    --nsg-name "$sg" \
    --resource-group "$rg" > $tmp_file 2>&1
  local ret=$?
  if [[ $ret -eq 0 ]]; then
    echo "  Revoked access on ${group_id}, protocol=${protocol}, port=${port} from ${cidr} $([[ $force == "force" ]] && echo "(forced)" || true)"
  elif [[ $ret -ne 0 && $(grep -c "The specified rule does not exist in this security group" $tmp_file) -ne 1 ]]; then
    cat $tmp_file
    rm -f $tmp_file
    exit $ret
  fi
  rm -f $tmp_file
  set -e
}
