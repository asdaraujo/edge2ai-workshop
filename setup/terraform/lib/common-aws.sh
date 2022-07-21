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
  run-on-all-clusters
  run-on-cluster
  start-instances
  stop-instances
  sync-ip-addresses
  update-registration-code
  upload-instance-details
  #
  rsync-resources
  tf-show
)

EC2_PRICES_URL_TEMPLATE=https://raw.githubusercontent.com/yeo/ec2.shop/master/data/REGION-ondemand.json

function get_instance_hourly_cost() {
  local instance_type=$1
  local ec2_prices_url=$(echo "$EC2_PRICES_URL_TEMPLATE" | sed "s/REGION/$TF_VAR_aws_region/")
  local tmp_file=/tmp/instance-cost.$$
  local ret=$(curl -w "%{http_code}" "$ec2_prices_url" -o $tmp_file --stderr /dev/null)
  if [[ $ret == 200 ]]; then
    jq -r '.prices[] | select(.attributes["aws:ec2:instanceType"] == "'"$instance_type"'").price.USD' $tmp_file
  fi
  rm -f $tmp_file
}

function validate_cloud_parameters() {
  if [[ ${TF_VAR_aws_profile:-} == "" && (${TF_VAR_aws_access_key_id:-} == "" || ${TF_VAR_aws_secret_access_key:-} == "") ]]; then
    echo "${C_RED}ERROR: One of the following must be set in the .env.${NAMESPACE} file:"
    echo "         - TF_VAR_aws_profile"
    echo "         - TF_VAR_aws_access_key_id and TF_VAR_aws_secret_access_key"
    echo "${C_NORMAL}"
    exit 1
  fi
  if [[ ${TF_VAR_aws_profile:-} != "" && (${TF_VAR_aws_access_key_id:-} != "" || ${TF_VAR_aws_secret_access_key:-} != "") ]]; then
    echo "${C_RED}ERROR: If TF_VAR_aws_profile is set, the following must be blank/unset in the .env.${NAMESPACE} file::"
    echo "         - TF_VAR_aws_access_key_id"
    echo "         - TF_VAR_aws_secret_access_key"
    echo "${C_NORMAL}"
    exit 1
  fi
  if [[ ${TF_VAR_aws_region:-} == "" ]]; then
    echo "${C_RED}ERROR: The following properties must be set in the .env.${NAMESPACE} file:"
    echo "         - TF_VAR_aws_region"
    echo "${C_NORMAL}"
    exit 1
  fi
  export AWS_DEFAULT_REGION=${TF_VAR_aws_region}
  if [[ ${TF_VAR_aws_profile:-} ]]; then
    export AWS_PROFILE=${TF_VAR_aws_profile}
  else
    export AWS_ACCESS_KEY_ID=${TF_VAR_aws_access_key_id:-}
    export AWS_SECRET_ACCESS_KEY=${TF_VAR_aws_secret_access_key:-}
  fi
}

function is_cli_available() {
  [[ $(get_cli_version) == "2"* ]] && echo yes || echo no
}

function get_cli_version() {
  aws --version 2>/dev/null | egrep -o '[0-9.][0-9.]*' | head -1 || true
}

function get_cloud_account_info() {
  AWS_PAGER="" aws sts get-caller-identity
}

function cloud_login() {
  aws sso login
}

function list_cloud_instances() {
  local instance_ids=$1
  # Returns: id, state, name, owner, enddate
  # Order by: state
  aws ec2 describe-instances --instance-ids $instance_ids | jq -r '.Reservations[].Instances[] | "\(.State.Name) \(.Tags[]? | select(.Key == "owner").Value) \(.Tags[]? | select(.Key == "enddate").Value) \(.Tags[]? | select(.Key == "Name").Value) \(.InstanceId)"' | sort -k2
}

function security_groups() {
  local sg_type=$1
  get_resource_attr aws_security_group "workshop_${sg_type}_sg" id
}

function start_instances() {
  local instance_ids=$1
  aws ec2 start-instances --instance-ids $instance_ids | yamlize
}

function stop_instances() {
  local instance_ids=$1
  aws ec2 stop-instances --instance-ids $instance_ids | yamlize
}

function terminate_instances() {
  local instance_ids=$1
  aws ec2 terminate-instances --instance-ids $instance_ids | yamlize
}

function describe_instances() {
  local instance_ids=$1
  aws ec2 describe-instances --instance-ids $instance_ids | yamlize
}

function set_instances_tag() {
  local instance_ids=$1
  local tag=$2
  local value=$3
  aws ec2 create-tags --resources $instance_ids --tags "Key=${tag},Value=${value}"
}

function is_instance_protected() {
  local instance_id=$1
  aws ec2 describe-instance-attribute --instance-id $instance_id --attribute disableApiTermination | jq -r '"\(.DisableApiTermination.Value)"'
}

function protect_instance() {
  local instance_id=$1
  aws ec2 modify-instance-attribute --instance-id $instance_id --disable-api-termination
}

function unprotect_instance() {
  local instance_id=$1
  aws ec2 modify-instance-attribute --instance-id $instance_id --no-disable-api-termination
}

function pre_launch_setup() {
  check_for_orphaned_keys

  # Sets the var below to prevent managed SGs from being added to the SGs we create
  if [ -s $TF_STATE ]; then
    export TF_VAR_managed_security_group_ids="[$(run_terraform show -json $TF_STATE | \
      jq -r '.values[]?.resources[]? | select(.type == "aws_security_group").values.id | "\"\(.)\""' | \
      tr "\n" "," | sed 's/,$//')]"
  fi
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
    cidr_filter='select(. == "'"$cidr"'") |'
  fi
  if [[ $protocol != "" ]]; then
    if [[ $protocol == "all" ]]; then
      protocol="-1"
    fi
    protocol_filter='select(.protocol == "'"$protocol"'") |'
  fi
  if [[ $port != "" ]]; then
    if [[ $port == *"-"* ]]; then
      from_port=${port%%-*}
      to_port=${port##*-}
    else
      from_port=$port
      to_port=$port
    fi
    port_filter='select(.from_port == '"$from_port"' and .to_port == '"$to_port"') |'
  fi
  if [[ $description != "" ]]; then
    description_filter='select(.description == "'"$description"'") |'
  fi
  ensure_tf_json_file
  jq -r '.values.root_module.resources[]?.values | select(.id == "'"$sg_id"'").ingress[] | '"$protocol_filter"' '"$port_filter"' '"$description_filter"' . as $parent | $parent.cidr_blocks[] | '"$cidr_filter"' "\(.) \(if $parent.protocol == "-1" then "all" else $parent.protocol end) \(if $parent.from_port == $parent.to_port then $parent.from_port else ($parent.from_port|tostring)+"-"+($parent.to_port|tostring) end)"' $TF_JSON_FILE
}

function add_sec_group_ingress_rule() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}
  local description=${5:-default}

  local tmp_file=/tmp/add-ingress.$$

  set +e
  aws ec2 authorize-security-group-ingress \
    --group-id "$group_id" \
    --ip-permissions "$(_ingress_permissions "$cidr" "$protocol" "$port" "$description")" > $tmp_file 2>&1
  local ret=$?
  if [[ $ret -eq 0 ]]; then
    echo "  Granted access on ${group_id}, protocol=${protocol}, port=${port} to ${cidr} $([[ $description == "" ]] || echo "($description)") $([[ $force == "force" ]] && echo " - (forced)" || true)"
  elif [[ $(grep -c "the specified rule .* already exists" $tmp_file) -ne 1 ]]; then
    cat $tmp_file
    rm -f $tmp_file
    exit $ret
  fi
  rm -f $tmp_file
  set -e
}

function remove_sec_group_ingress_rule() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}

  local tmp_file=/tmp/remove-ingress.$$

  set +e
  aws ec2 revoke-security-group-ingress \
    --group-id "$group_id" \
    --ip-permissions "$(_ingress_permissions "$cidr" "$protocol" "$port")" > $tmp_file 2>&1
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

#
# PRIVATE FUNCTIONS
#

function _ingress_permissions() {
  local cidr=$1
  local protocol=$2
  local port=$3
  local description=${4:-}

  local port_option=""
  local proto=$protocol
  if [[ $protocol == "all" ]]; then
     proto=-1
  else
    if [[ $port == "" ]]; then
      echo "ERROR: Port is required for protocol $protocol"
      exit 1
    fi
    if [[ $port == "all" ]]; then
      port=0
    fi
    if [[ $port == *"-"* ]]; then
      from_port=${port%%-*}
      to_port=${port##*-}
    else
      from_port=$port
      to_port=$port
    fi
    port_option="FromPort=${from_port},ToPort=${to_port},"
  fi
  if [[ $description != "" ]]; then
    description=",Description=$description"
  fi
  if [[ $(expr "$cidr" : '.*:') -gt 0 ]]; then
    # IPv6
    iprange="Ipv6Ranges=[{CidrIpv6=${cidr}${description}}]"
  else
    # IPv4
    iprange="IpRanges=[{CidrIp=${cidr}${description}}]"
  fi
  echo "IpProtocol=${proto},${port_option}${iprange}"
}

