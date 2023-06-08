#!/bin/bash

source $BASE_DIR/lib/common-basics.sh

DOCKER_REPO=asdaraujo/edge2ai-workshop
DEFAULT_DOCKER_IMAGE=${DOCKER_REPO}:latest
GITHUB_FQDN="github.com"
GITHUB_REPO=cloudera-labs/edge2ai-workshop
GITHUB_BRANCH=trunk

BUILD_FILE=.build
STACK_BUILD_FILE=.stack.build
LAST_STACK_CHECK_FILE=$BASE_DIR/.last.stack.build.check
PUBLIC_IPS_FILE=$BASE_DIR/.hosts.$$
LICENSE_FILE_MOUNTPOINT=/tmp/license.file

BASE_PROVIDER_DIR=$BASE_DIR/providers

THE_PWD=Supersecret1

OPTIONAL_VARS="TF_VAR_registration_code|TF_VAR_aws_profile|TF_VAR_aws_access_key_id|TF_VAR_aws_secret_access_key|TF_VAR_azure_subscription_id|TF_VAR_azure_tenant_id|TF_VAR_cdp_license_file"

unset SSH_AUTH_SOCK SSH_AGENT_PID

function check_version() {
  if [[ ! -f $BASE_DIR/NO_VERSION_CHECK ]]; then

    # First, try automated refresh using git

    if [[ $(which git 2>/dev/null) ]]; then
      #
      mkdir -p ~/.ssh

      # check github can be resolved
      if ! nslookup "$GITHUB_FQDN" > /dev/null 2>&1; then
        echo "${C_RED}ERROR: Unable to resolve the IP for ${GITHUB_FQDN}${C_NORMAL}"
        abort
      fi

      # git is installed
      remote=$(set +e; git status | grep "Your branch" | egrep -o "[^']*/${GITHUB_BRANCH}\>" | sed 's#/.*##'; true)
      if [[ $remote != "" ]]; then
        # current branch points to the remote $GITHUB_BRANCH branch
        uri=$(set +e; git remote -v | egrep "^ *$remote\s.*\(fetch\)" | awk '{print $2}'; true)
        if [[ $uri =~ "$GITHUB_REPO" ]]; then
          # remote repo is the official repo
          GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git fetch > /dev/null 2>&1 || true
          if [[ $(git status) =~ "Your branch is up to date" ]]; then
            echo "Your edge2ai-workshop repo seems to be up to date."
            return
          elif [[ $(git status) =~ "can be fast-forwarded" ]]; then
            echo "$C_RED"
            echo "There is an update available for the edge2ai-workshop."
            echo -n "Do you want to refresh your local repo now? (y|n) $C_NORMAL"
            read confirm
            if [[ $confirm == Y || $confirm == y ]]; then
              git reset --hard || true
              git pull || true
              if [[ $(git status) =~ "Your branch is up to date" ]]; then
                echo "$C_YELLOW"
                echo "   Congratulations! The update completed successfully! Please run the launch command again."
                echo "$C_NORMAL"
              else
                echo "$C_RED"
                echo "Oops! Apparently something went wrong during the update."
                echo "Try refreshing it manually with the commands below and run launch again when finished:"
                echo ""
                echo "   git fetch"
                echo "   git pull"
                echo "$C_NORMAL"
              fi
              exit
            fi
            return
          fi
        fi
      fi
    fi

    # Cannot use git. Will check using curl and suggest manual refresh is needed

    # Get current build timestamp
    dir=$PWD
    while [[ $dir != / && ! -f $dir/$BUILD_FILE ]]; do
      dir=$(dirname $dir)
    done
    this_build=$(head -1 $dir/$BUILD_FILE 2>/dev/null | grep -o "^[0-9]\{14\}" | head -1)
    latest_build=$(curl "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/$BUILD_FILE" 2>/dev/null | head -1 | grep -o "^[0-9]\{14\}" | head -1)
    if [[ $latest_build != "" ]]; then
      if [[ $this_build == "" || $this_build < $latest_build ]]; then
        echo "$C_RED"
        echo "There is an update available for the edge2ai-workshop."
        echo "Please check the GitHub repository below and get the latest version from there:"
        echo ""
        echo "   https://${GITHUB_FQDN}/${GITHUB_REPO}/"
        echo ""
        echo -n "Do you want to perform the update now? (Y|n) $C_NORMAL"
        read confirm
        if [[ $confirm == Y || $confirm == y ]]; then
          echo "Ok. Please re-run the launch command after you finish the update."
          exit
        fi
      else
        echo "edge2ai-workshop repo is up to date."
      fi
    else
      echo "Cannot check for updates now. Continuing with the current version."
    fi
  fi
}

function check_stack_version() {
  if [[ ! -f $BASE_DIR/NO_VERSION_CHECK ]]; then
    # Get last check timestamp
    local last_stack_check=$(head -1 $LAST_STACK_CHECK_FILE 2>/dev/null | grep -o "^[0-9]\{14\}" | head -1 || true)
    local latest_stack_in_repo=$(curl "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/$STACK_BUILD_FILE" 2>/dev/null | head -1 | grep -o "^[0-9]\{14\}" | head -1 || true)
    local latest_stack_in_use=$(grep -h STACK_VERSION $BASE_DIR/resources/stack*.sh 2>/dev/null | egrep -o "\b[0-9]{14}\b" | sort -u | tail -1 || true)
    echo "$latest_stack_in_repo" > $LAST_STACK_CHECK_FILE
    if [[ $latest_stack_in_repo != "" ]]; then
      if [[ ($latest_stack_in_use == "" || $latest_stack_in_use < $latest_stack_in_repo) && \
            ($last_stack_check == "" || $last_stack_check < $latest_stack_in_repo) ]]; then
        echo "$C_YELLOW"
        echo "There are new STACK definitions available at the URL below (VPN required):"
        echo ""
        echo "   http://tiny.cloudera.com/workshop-templates/"
        echo ""
        echo "Please consider downloading and updating your stack files to the latest ones."
        echo ""
        echo -n "Do you want to proceed with the launch now? (y|N) $C_NORMAL"
        read confirm
        if [[ $confirm != Y && $confirm != y ]]; then
          echo "Ok. Please re-run the launch command after you finish the stack update."
          exit
        fi
      fi
    fi
  fi
}

function is_docker_running() {
  docker info >/dev/null 2>&1 && echo "yes" || echo "no"
}

function create_ips_file() {
  # Sometimes docker fails to resolve IP addresses for public sites, like github.com
  # To avoid problems, we resolve these outside of the docker container
  rm -f $PUBLIC_IPS_FILE
  for fqdn in \
    github.com \
    ifconfig.me \
    frightanic.com \
    raw.githubusercontent.com \
    auth.docker.io \
    index.docker.io \
    ; do
    echo "$(dig $fqdn +short | head -1) $fqdn" >> $PUBLIC_IPS_FILE
  done
}

function use_ips_file() {
  # Ensure we incorporate the good IPs into /etc/hosts
  if [[ ${HOSTS_ADD:-} != "" && -f $BASE_DIR/$HOSTS_ADD ]]; then
    cat $BASE_DIR/$HOSTS_ADD >> /etc/hosts
    rm -f $BASE_DIR/$HOSTS_ADD
  fi
}

function is_docker_image_stale() {
  local image_id=$(docker inspect $DEFAULT_DOCKER_IMAGE 2>/dev/null | grep '"Id":' | awk -F\" '{print $4}')
  local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${DOCKER_REPO}:pull" | grep '"token":' | awk -F\" '{print $4}')
  local latest_image_id=$(curl -s -H "Authorization: Bearer $token" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "https://index.docker.io/v2/${DOCKER_REPO}/manifests/latest" | grep -A4 '"config":' | grep '"digest":' | awk -F\" '{print $4}')
  if [[ $image_id != $latest_image_id ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

function maybe_launch_docker() {
  if [[ "${NO_DOCKER:-}" == "" && "${NO_DOCKER_EXEC:-}" == "" && "$(is_docker_running)" == "yes" ]]; then
    create_ips_file

    local docker_img=${EDGE2AI_DOCKER_IMAGE:-$DEFAULT_DOCKER_IMAGE}
    if [[ ${NO_DOCKER_MSG:-} == "" ]]; then
      echo -e "${C_DIM}Using docker image: ${docker_img}${C_NORMAL}"
      export NO_DOCKER_MSG=1
    fi
    if [[ "${NO_DOCKER_PULL:-}" == "" && $docker_img == $DEFAULT_DOCKER_IMAGE ]]; then
      if [[ $(is_docker_image_stale) == "yes" ]]; then
        docker pull --platform linux/amd64 $docker_img || true
      fi
    fi
    for dir in $HOME/.aws $HOME/.azure; do
      if [[ ! -d $dir ]]; then
        mkdir -p $dir
        chmod 755 $dir
      fi
    done
    local docker_cmd=./$(basename $0)
    local cmd=(
      exec docker run -ti --rm
        --platform linux/amd64
        --detach-keys="ctrl-@"
        --entrypoint=""
        -v $BASE_DIR/../..:/edge2ai-workshop
        -v $HOME/.aws:/root/.aws
        -v $HOME/.azure:/root/.azure
        -e DEBUG=${DEBUG:-}
        -e NO_PROMPT=${NO_PROMPT:-}
        -e NO_LOG_FETCH=${NO_LOG_FETCH:-}
        -e HOSTS_ADD=$(basename $PUBLIC_IPS_FILE)
    )
    if [[ ! -z ${TF_VAR_cdp_license_file:-} ]]; then
      cmd=("${cmd[@]}" -v "$TF_VAR_cdp_license_file:$LICENSE_FILE_MOUNTPOINT")
    fi
    cmd=(
      "${cmd[@]}"
        $docker_img
        $docker_cmd $*
    )
    "${cmd[@]}"
  fi
  if [[ "${INSIDE_DOCKER_CONTAINER:-0}" == "0" ]]; then
    if [[ ${NO_DOCKER_MSG:-} == "" ]]; then
      echo -e "${C_DIM}Running locally (no docker)${C_NORMAL}"
      export NO_DOCKER_MSG=1
    fi
  else
    use_ips_file
  fi
}

function check_for_caffeine() {
  if [[ ${NO_CAFFEINE:-} == "" && ${CAFFEINATE_ME:-} != "" && ${CAFFEINATED:-} == "" ]]; then
    set +e
    which caffeinate > /dev/null 2>&1
    local no_caffeinate=$?
    local system=$(uname -s 2> /dev/null | tr 'A-Z' 'a-z')
    set -e
    if [[ $no_caffeinate -eq 0 ]]; then
      if [[ $system == "darwin" ]]; then
        CAFFEINATED=1 exec caffeinate -i "$0" "$@"
      elif [[ $system == "linux" ]]; then
        CAFFEINATED=1 exec caffeinate "$0" "$@"
      fi
    fi
  fi
}

function try_in_docker() {
  local namespace=$1
  shift
  local -a cmd=("$@")
  if [[ "${NO_DOCKER:-}" == "" && "$(is_docker_running)" == "yes" ]]; then
    local docker_img=${EDGE2AI_DOCKER_IMAGE:-$DEFAULT_DOCKER_IMAGE}
    local cmd=(
      exec docker run --rm
        --platform linux/amd64
        --detach-keys="ctrl-@"
        --entrypoint=""
        -v $BASE_DIR/../..:/edge2ai-workshop
        -v $HOME/.aws:/root/.aws
        -v $HOME/.azure:/root/.azure
        -e DEBUG=${DEBUG:-}
        -e NO_PROMPT=${NO_PROMPT:-}
        -e NO_LOG_FETCH=${NO_LOG_FETCH:-}
        -e HOSTS_ADD=$(basename $PUBLIC_IPS_FILE)
    )
    if [[ ! -z ${TF_VAR_cdp_license_file:-} ]]; then
      cmd=("${cmd[@]}" -v "$TF_VAR_cdp_license_file:$LICENSE_FILE_MOUNTPOINT")
    fi
    cmd=(
      "${cmd[@]}"
        $docker_img
        /bin/bash -c "cd /edge2ai-workshop/setup/terraform; export BASE_DIR=\$PWD; export NO_DOCKER_MSG=1; source lib/common.sh; load_env $namespace; ${cmd[*]}"
    )
    "${cmd[@]}"
  else
    (load_env $namespace; eval "${cmd[*]}")
  fi
}

function check_python_modules() {
  python -c '
import sys

if sys.version_info.major < 3:
  print("ERROR: You are currently using the following Python version: " + sys.version.replace("\n", ""))
  print("ERROR: Please switch to Python 3 to use this script.")
  exit(1)

missing_modules = []
try:
  import yaml
except:
  print("ERROR: Python module \"PyYAML\" not found.")
  missing_modules.append("pyyaml")

try:
  import jinja2
except:
  print("ERROR: Python module \"Jinja2\" not found.")
  missing_modules.append("jinja2")

try:
  import boto3
except:
  print("ERROR: Python module \"Boto3\" not found.")
  missing_modules.append("boto3")

if missing_modules:
  print("Please install the missing modules with the command below and try again:")
  print("\n  pip install " + " ".join(missing_modules) + "\n")
  exit(1)
'
}

function get_env_file_path() {
  local namespace=$1
  local env_file=$BASE_DIR/.env.$namespace
  if [ "$namespace" == "default" ]; then
    env_file=$BASE_DIR/.env
  fi
  echo $env_file
}

function check_implemented_functionality() {
  local script_name=$0
  local base_name=$(basename "$script_name" | sed 's/\.[^.]*//')
  if [[ $base_name == "0" || $base_name == "bash" ]]; then
    return
  fi
  for script in "${AVAILABLE_SCRIPTS[@]:-}"; do
    if [[ $base_name == $script ]]; then
      return
    fi
  done
  echo "${C_YELLOW}WARNING: Script $script_name is not yet implemented for the $TF_VAR_cloud_provider cloud provider.${C_NORMAL}"
  abort
}

function ensure_cloud_session() {
  validate_cloud_parameters
  if [[ ${SKIP_CLOUD_LOGIN:-0} -ne 1 ]]; then
    if [[ $(is_cli_available) == "yes" ]]; then
      local tmp_file=/tmp/check_cloud_login.${NAMESPACE}.$$
      if ! get_cloud_account_info > $tmp_file 2>&1; then
        echo "The previous cloud session has expired. Issuing a new login request..."
        cloud_login
        if ! get_cloud_account_info > $tmp_file 2>&1; then
          echo "${C_RED}ERROR: Failed to login. Please review the configuration in the .env.$NAMESPACE file."
          echo "Error output:"
          cat $tmp_file
          rm -f $tmp_file
          echo "${C_NORMAL}"
          abort
        fi
      fi
    fi
  fi
}

function load_env() {
  local namespace=$1
  local env_file=$(get_env_file_path $namespace)

  check_env_files

  if [[ ! -f $env_file ]]; then
    echo ""
    echo "The namespace [$namespace] has not been configured."
    echo "1. Create the environment by copying the environment template:"
    echo "     cp .env.template .env.<namespace_name>"
    echo "2. Review and configure .env.<namespace_name> appropriately."
    echo ""
    abort
  fi
  source $env_file
  export NAMESPACE=$namespace

  export TF_VAR_cloud_provider=${TF_VAR_cloud_provider:-aws}
  local provider_common=$BASE_DIR/lib/common-${TF_VAR_cloud_provider}.sh
  if [[ -f $provider_common ]]; then
    source $provider_common
  fi
  check_implemented_functionality
  if [[ ${NEED_CLOUD_SESSION:-} != "" ]]; then
    ensure_cloud_session
  fi

  NAMESPACE_DIR=$BASE_DIR/namespaces/$namespace
  PROVIDER_DIR=$BASE_PROVIDER_DIR/${TF_VAR_cloud_provider}
  NAMESPACE_PROVIDER_DIR=$NAMESPACE_DIR/provider
  TF_JSON_FILE=$NAMESPACE_DIR/${namespace}.tf.json
  REGISTRATION_CODE_FILE=$NAMESPACE_DIR/registration.code
  TF_STATE=$NAMESPACE_DIR/terraform.state

  export TF_VAR_namespace=$NAMESPACE
  export TF_VAR_name_prefix=$(echo "$namespace" | tr "A-Z" "a-z")
  export TF_VAR_key_name="${TF_VAR_name_prefix}-$(echo -n "$TF_VAR_owner" | base64)"
  export TF_VAR_web_key_name="${TF_VAR_name_prefix}-$(echo -n "$TF_VAR_owner" | base64)-web"

  export TF_VAR_ssh_private_key=$NAMESPACE_DIR/${TF_VAR_key_name}.pem
  export TF_VAR_ssh_public_key=$NAMESPACE_DIR/${TF_VAR_key_name}.pem.pub
  export TF_VAR_web_ssh_private_key=$NAMESPACE_DIR/${TF_VAR_web_key_name}.pem
  export TF_VAR_web_ssh_public_key=$NAMESPACE_DIR/${TF_VAR_web_key_name}.pem.pub
  export TF_VAR_my_public_ip=$(curl -sL http://ifconfig.me || curl -sL http://api.ipify.org/ || curl -sL https://ipinfo.io/ip)

  normalize_boolean TF_VAR_use_elastic_ip false
  normalize_boolean TF_VAR_pvc_data_services false
  normalize_boolean TF_VAR_deploy_cdsw_model true

  export TF_VAR_cdp_license_file_original=${TF_VAR_cdp_license_file:-}
  export TF_VAR_cdp_license_file=$(get_license_file_path)
}

function get_license_file_path() {
  if [[ -z ${TF_VAR_cdp_license_file:-} ]]; then
    echo ""
  elif [[ -s $TF_VAR_cdp_license_file ]]; then
    echo "$TF_VAR_cdp_license_file"
  elif [[ $(df | grep "$LICENSE_FILE_MOUNTPOINT" | wc -l) -eq 1 ]]; then
    # we are running inside docker
    echo "$LICENSE_FILE_MOUNTPOINT"
  else
    echo "/file/not/found"
  fi
}

function validate_license_file() {
  if [[ ! -z ${TF_VAR_cdp_license_file:-} && ! -s $TF_VAR_cdp_license_file ]]; then
    echo "${C_RED}ERROR: License file "\""${TF_VAR_cdp_license_file_original}"\"" not found.${C_NORMAL}"
    abort
  fi
}

function license_metadata() {
  egrep -v "^([A-Za-z0-9=-])" "$TF_VAR_cdp_license_file"
}

function validate_license() {
  [[ -z ${TF_VAR_cdp_license_file:-} ]] && return
  validate_license_file

  [[ $(egrep -c 'BEGIN PGP SIGNED MESSAGE|BEGIN PGP SIGNATURE|END PGP SIGNATURE' "$TF_VAR_cdp_license_file") -eq 3 ]] && \
  (license_metadata | jq . > /dev/null) && \
  [[ ! -z $(license_metadata | jq -r .name) ]] && \
  [[ ! -z $(license_metadata | jq -r .uuid) ]] && \
  [[ ! -z $(license_metadata | jq -r .startDate) && $(license_metadata | jq -r .startDate) < "$(date +%Y-%m-%d)" ]] && \
  [[ ! -z $(license_metadata | jq -r .expirationDate) && $(license_metadata | jq -r .expirationDate) > "$(date +%Y-%m-%d)" ]] && \
  return

  echo "${C_RED}ERROR: The license in file "\""${TF_VAR_cdp_license_file_original}"\"" is either invalid or expired.${C_NORMAL}"
  abort
}

function get_remote_repo_username() {
  validate_license
  grep '"uuid"' "$TF_VAR_cdp_license_file" | awk -F\" '{printf "%s", $4}'
}

function get_remote_repo_password() {
  validate_license
  local name=$(grep '"name"' "$TF_VAR_cdp_license_file" | awk -F\" '{print $4}')
  echo -n "${name}$(get_remote_repo_username)" | openssl dgst -sha256 -hex | egrep -o '[a-f0-9]{12}' | head -1
}

function normalize_boolean() {
  local property=$1
  local default=$2
  value="$(eval "echo "\""\${${property}:-${default}}"\" | tr A-Z a-z)"
  if [[ "$value" == "yes" || "$value" == "true" || "$value" == "1" ]]; then
    eval "export $property=true"
  elif [[ "$value" == "no" || "$value" == "false" || "$value" == "0" ]]; then
    eval "export $property=false"
  else
    echo "${C_RED}ERROR: Property $property has an invalid value: "\""$value"\"". Valid values are: true, false, yes, no, 1, 0.${C_NORMAL}"
    abort
  fi
  export TF_VAR_use_elastic_ip
}

function run_terraform() {
  local args=("$@")
  local provider_dir=$NAMESPACE_PROVIDER_DIR
  if [[ ! -d $NAMESPACE_PROVIDER_DIR ]]; then
    if [[ -f $TF_STATE ]]; then
      # Deployment already exists but this is prior to multi-provider support and there is no NAMESPACE_PROVIDER_DIR
      # Use the base provider dir in this case
      provider_dir=$PROVIDER_DIR
    else
      # New deployment, so we can create a new NAMESPACE_PROVIDER_DIR
      mkdir -p $NAMESPACE_PROVIDER_DIR
      cp -r $PROVIDER_DIR/* $NAMESPACE_PROVIDER_DIR/
      provider_dir=$NAMESPACE_PROVIDER_DIR
    fi
  fi
  check_terraform_version
  pushd $provider_dir > /dev/null
  export TF_VAR_base_dir=$BASE_DIR
  date >> $NAMESPACE_DIR/terraform.log
  echo "Command: validate" >> $NAMESPACE_DIR/terraform.log
  set +e
  $TERRAFORM validate >> $NAMESPACE_DIR/terraform.log 2>&1
  local ret=$?
  set -e
  if [[ $ret -ne 0 ]]; then
    echo "Command: init -upgrade" >> $NAMESPACE_DIR/terraform.log
    # Sometimes there are issues downloading plugins. So it retries when needed...
    retry_if_needed 10 1 "$TERRAFORM init -upgrade" >> $NAMESPACE_DIR/terraform.log 2>&1
  fi
  echo "Command: ${args[@]}" >> $NAMESPACE_DIR/terraform.log
  $TERRAFORM "${args[@]}"
  popd > /dev/null
}

function check_terraform_version() {
  # if there's a remnant of a state file, ensures it matches the Terraform version
  local state_version="*"
  if [[ -f $TF_STATE ]]; then
    # if the state file is empty of resource, just remove it and start fresh
    if [[ $(jq '.resources | length' $TF_STATE) -eq 0 ]]; then
      echo '{"version":4}' > $TF_STATE
    else
      state_version=$(jq -r '.terraform_version' $TF_STATE | egrep -o "^[0-9]+\.[0-9]+")
    fi
  fi

  for tf_binary in \
    ${TERRAFORM:-} \
    $(which terraform | grep -v not.found) \
    ${TERRAFORM14:-} \
    ${TERRAFORM12:-} \
    ; do
    local tf_version=$($tf_binary version | grep Terraform.v | egrep -o "[0-9]+\.[0-9]+")
    if [[ $state_version == "*" || $state_version == $tf_version ]]; then
      TERRAFORM=$tf_binary
      return
    fi
  done
  echo "${C_RED}ERROR: Could not find a version of Terraform that matches the state file $TF_STATE version ($state_version)." >&2
  echo "       Please install Terraform v${state_version} and set/export the TERRAFORM environment variable with its path.${C_NORMAL}" >&2
  echo "       If you are using a Docker container, please ensure that Docker is running." >&2
  abort
}

function ensure_ulimit() {
  local ulimit_target=10000
  local nofile=$(ulimit -n)
  if [ "$nofile" != "unlimited" -a "$nofile" -lt $ulimit_target ]; then
    ulimit -n $ulimit_target 2>/dev/null || true
    nofile=$(ulimit -n)
    if [ "$nofile" != "unlimited" -a "$nofile" -lt $ulimit_target ]; then
      echo "WARNING: The maximum number of open file handles for this session is low ($nofile)."
      echo "         If the launch fails with the message "Too many open files", consider increasing"
      echo "         it with the ulimit command and try again."
    fi
  fi
}

function ensure_key_pair() {
  local priv_key=$1
  if [ -f ${priv_key} ]; then
    log "Private key already exists: ${priv_key}. Will reuse it."
  else
    log "Creating key pair"
    umask 0277
    ssh-keygen -f ${priv_key} -N "" -m PEM -t rsa -b 2048
    umask 0022
    log "Private key created: ${priv_key}"
  fi
}

function aws_list_key_pairs() {
  if [[ $TF_VAR_aws_profile != "" ]]; then
    options="--profile $TF_VAR_aws_profile"
  else
    options=""
  fi
  aws \
    --region $TF_VAR_aws_region \
    $options \
    ec2 describe-key-pairs \
      --filters '[{"Name": "key-name","Values":["'"${TF_VAR_key_name}"'","'"${TF_VAR_web_key_name}"'"]}]' | \
  jq -r '.KeyPairs[].KeyName' | tr '\n' ',' | sed 's/,$//'
}

function aws_delete_key_pairs() {
  local keys=$1
  if [[ $TF_VAR_aws_profile != "" ]]; then
    options="--profile $TF_VAR_aws_profile"
  else
    options=""
  fi
  for key_name in $(echo "$keys" | sed 's/,/ /g'); do
    echo "Deleting key pair [$key_name]"
    aws \
      --region $TF_VAR_aws_region \
      $options \
      ec2 delete-key-pair --key-name "$key_name"
  done
}

function check_for_orphaned_keys() {
  if [[ $TF_VAR_cloud_provider != "aws" ]]; then
    return
  fi
  if [[ ( ! -f $TF_STATE ) || ( -f $TF_STATE && $(jq '.resources[]' $TF_STATE) == "" ) ]]; then
    # there's no state record, so there should be no deployments
    keys=$(aws_list_key_pairs)
    if [[ $keys != "" ]]; then
      echo "${C_YELLOW}WARNING: The following keys seem to be orphaned in your AWS environment: ${keys}"
      echo "         This may have happened either because your last deployment wasn't terminated gracefully"
      echo "         or because you launched it from a different directory."
      echo ""
      echo "         You can choose to overwrite these keys, but if the previous environment still exists"
      echo "         you will lose access to it."
      echo ""
      echo -n "Do you want to overwrite these key pairs? (y/N) "
      read CONFIRM
      if [[ $(echo "$CONFIRM" | tr "a-z" "A-Z") != "Y" ]]; then
        echo "Ensure the keys listed above don't exist before trying this command again."
        echo "Alternatively, launch the environment using a different namespace."
        exit 0
      else
        # Delete keys from the AWS environment
        aws_delete_key_pairs "$keys"
      fi
      echo "${C_NORMAL}"
    fi
  fi
}

function ensure_key_pairs() {
  for key in ${TF_VAR_ssh_private_key} ${TF_VAR_web_ssh_private_key}; do
    ensure_key_pair $key
  done
}

function delete_key_pair() {
  local key_name=$1
  local priv_key=$2
  local pub_key=$3
  if [ -f ${priv_key} ]; then
    log "Deleting key pair [${key_name}]"
    mv -f ${priv_key} ${priv_key}.OLD.$(date +%s) || true
    mv -f ${pub_key} ${pub_key}.OLD.$(date +%s) || true
  fi
}

function delete_key_pairs() {
  set -- ${TF_VAR_key_name}     ${TF_VAR_ssh_private_key}     ${TF_VAR_ssh_public_key} \
         ${TF_VAR_web_key_name} ${TF_VAR_web_ssh_private_key} ${TF_VAR_web_ssh_public_key}
  while [ $# -gt 0 ]; do
    local key_name=$1; shift
    local priv_key=$1; shift
    local pub_key=$1; shift
    delete_key_pair $key_name $priv_key $pub_key
  done
}

function public_dns() {
  local instance_id=$1
  if [[ "$instance_id" == "web" ]]; then
    web_instance | web_attr public_dns
  elif [[ "$instance_id" == "ipa" ]]; then
    ipa_instance | ipa_attr public_dns
  elif [[ "$instance_id" == "ecs"* ]]; then
    ecs_instances ${instance_id#ecs} | cluster_attr public_dns
  else
    cluster_instances $instance_id | cluster_attr public_dns
  fi
}

function public_ip() {
  local cluster_number=$1
  cluster_instances $cluster_number | cluster_attr public_ip
}

function private_ip() {
  local cluster_number=$1
  cluster_instances $cluster_number | cluster_attr private_ip
}

function check_for_jq() {
  set +e
  local ret=0
  jq --version > /dev/null 2>&1
  ret=$?
  set -e
  if [ $ret != 0 ]; then
    echo "ERROR: The "jq" tool is not installed and it is required."
    echo "       Please install jq and try again. Check the documentation for"
    echo "       more details."
    abort
  fi
}

function check_file_staleness() {
  # check if environment files are missing parameters
  local basefile=$1
  local compare=$2
  local base_variables=$(grep -E "^ *(export){0,1} *[a-zA-Z0-9_]*=" $basefile | sed -E 's/ *(export){0,1} *//;s/=.*//' | sort -u)
  local stale=0
  set +e
  for var in $base_variables; do
    grep -E "^ *(export){0,1} *$var=" $compare > /dev/null
    if [ $? != 0 ]; then
      line=$(grep "^ *export  *$var=" $basefile)
      echo "${line}" >> $compare
      echo "${C_BLUE}INFO: Configuration file $compare has been updated with the following property: ${line}.${C_NORMAL}" >&2
    fi
  done
  not_set=$(grep -E "^ *(export){0,1} *[a-zA-Z0-9_]*=" $compare | sed -E 's/ *(export){0,1} *//;s/="?<[A-Z_]*>"?$/=/g;s/""//g' | egrep "CHANGE_ME|REPLACE_ME|=$" | sed 's/=//' | egrep -v "$OPTIONAL_VARS" | tr "\n" "," | sed 's/,$//')
  if [ "$not_set" != "" ]; then
    echo "${C_RED}ERROR: Configuration file $compare has the following unset properties: ${not_set}.${C_NORMAL}" >&2
    stale=1
  fi
  set -e
  echo $stale
}

function presign_urls() {
  local stack_file=$1
  python $BASE_DIR/presign_urls.py "$stack_file"
}

function validate_env() {
  local template_file=$BASE_DIR/.env.template
  local compare_file=$(get_env_file_path $NAMESPACE)
  if [[ $compare_file != "" && ! -f $compare_file ]]; then
    echo "${C_RED}ERROR: The specified enviroment file ($compare_file) does not exist.${C_NORMAL}" >&2
    abort
  fi
  if [ ! -f $template_file ]; then
    echo "${C_RED}ERROR: Cannot find the template file $template_file.${C_NORMAL}" >&2
    abort
  fi
  if [ "$(check_file_staleness $template_file $compare_file)" != "0" ]; then
      cat >&2 <<EOF

${C_RED}ERROR: Please fix the problems above in the file $compare_file and try again.${C_NORMAL}
       If this configuration was working before, you may have upgraded to a new version
       of the workshop that requires additional properties.
       You can refer to the template $template_file for a list of all the required properties.
EOF
      abort
  fi

  if [[ $TF_VAR_pvc_data_services == "true" ]]; then
    if [[ -z ${TF_VAR_cdp_license_file:-} ]]; then
      echo "${C_RED}ERROR: When TF_VAR_pvc_data_services=true you must specify a license file using the TF_VAR_cdp_license_file property.${C_NORMAL}"
      abort
    fi
  fi

  validate_license
}

function kerb_auth_for_cluster() {
  local cluster_id=$1
  local public_dns=$(public_dns $cluster_id)
  if [ "$ENABLE_KERBEROS" == "yes" ]; then
    export KRB5_CONFIG=$NAMESPACE_DIR/krb5.conf.$cluster_id
    cat > $KRB5_CONFIG <<EOF
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_realm = WORKSHOP.COM
 udp_preference_limit = 1
 kdc_timeout = 3

[realms]
 WORKSHOP.COM = {
  kdc = tcp/$public_dns
  kdc = $public_dns
  admin_server = $public_dns
 }

[domain_realm]
 .workshop.com = WORKSHOP.COM
 workshop.com = WORKSHOP.COM
EOF
    export KEYTAB=$NAMESPACE_DIR/workshop.keytab
    rm -f $KEYTAB
    scp -q -o StrictHostKeyChecking=no -i $TF_VAR_ssh_private_key $TF_VAR_ssh_username@$(public_dns $CLUSTER_ID):/keytabs/workshop.keytab $KEYTAB
    export KRB5CCNAME=/tmp/workshop.$$
    kinit -kt $KEYTAB workshop
  fi
}

function remaining_days() {
  local enddate=$1
  python -c "
from datetime import datetime, timedelta
dt = datetime.now()
dt = dt.replace(hour=0, minute=0, second=0, microsecond=0)
print((datetime.strptime('$enddate', '%m%d%Y') - dt).days)
"
}

function wait_for_web() {
  local web_ip_address=${1:-$(web_instance | web_attr public_ip)}
  local retries=120
  local ret=0
  while [[ $retries -gt "0" ]]; do
    set +e
    ret=$(curl --connect-timeout 5 -s -o /dev/null -w "%{http_code}" -k -H "Content-Type: application/json" "http://${web_ip_address}/api/ping")
    set -e
    if [ "$ret" == "200" ]; then
      break
    fi
    retries=$((retries - 1))
    if [[ $retries -gt 0 ]]; then
      echo "Waiting for web server to be ready... ($retries retries left)"
      sleep 1
    fi
  done
  if [ "$ret" == "200" ]; then
    echo "Web server is ready!"
  else
    echo "ERROR: Web server didn't respond successfully."
    return 1
  fi
}

function retry_if_needed() {
  local retries=$1
  local wait_secs=$2
  local cmd=$3
  local ret=0
  while [[ $retries -ge 0 ]]; do
    set +e
    eval "$cmd"
    ret=$?
    set -e
    if [[ $ret -eq 0 ]]; then
      return 0
    else
      retries=$((retries-1))
      if [[ $retries -lt 0 ]]; then
        return $ret
      fi
    fi
    sleep $wait_secs
    echo "Retrying command [$cmd]"
  done
}

function add_ingress() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}
  local description=${5:-default}
  local force=${6:-}

  ingress=$(get_ingress "$group_id" "$cidr" "$protocol" "$port")
  if [[ $ingress == "" || $force == "force" ]]; then
    add_sec_group_ingress_rule "$group_id" "$cidr" "$protocol" "$port" "$description"
  fi
}

function remove_ingress() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}
  local force=${5:-}
  local tmp_file=/tmp/remove-ingress.$$

  ingress=$(get_ingress "$group_id" "$cidr" "$protocol" "$port")
  if [[ $ingress != "" || $force == "force" ]]; then
    remove_sec_group_ingress_rule "$group_id" "$cidr" "$protocol" "$port"
  fi
}

#
# Terraform refresh and parsing functions
#

function refresh_tf_state() {
  echo "${C_DIM}Refreshing deployment state. Please wait...${C_NORMAL}" >&2
  pushd $BASE_DIR > /dev/null
  run_terraform refresh -state $TF_STATE > /dev/null
  popd > /dev/null
}

function refresh_tf_json() {
  rm -f $TF_JSON_FILE
  pushd $BASE_DIR > /dev/null
  run_terraform show -json $TF_STATE > $TF_JSON_FILE
  popd > /dev/null
  # For some strange reason, the writing to TF_JSON_FILE above happens asynchronously.
  # We need to wait for the file to be flushed completely before we continue.
  local wait_secs=60
  while [[ $wait_secs -gt 0 ]]; do
    if [[ -s $TF_JSON_FILE ]]; then
      sleep 1
      break
    fi
    wait_secs=$((wait_secs - 1))
    sleep 1
  done
}

function ensure_tf_json_file() {
  if [[ -s $TF_STATE && ( ! -s $TF_JSON_FILE || $TF_STATE -nt $TF_JSON_FILE ) ]]; then
    refresh_tf_json
  fi
}

function get_resource_attr() {
  local resource_type=$1
  local name=$2
  local attr=$3
  local index=${4:-}
  local attrs=""
  if [[ $name == *"="* ]]; then
    # this is a filter instead of just a name
    name_filter="$name"
  else
    name_filter='.name == "'"$name"'"'
  fi
  for a in $attr; do
    if [[ $attrs != "" ]]; then
      attrs="$attrs "
    fi
    if [[ ${a:0:1} == "." ]]; then
      attrs="$attrs\($a)"
    else
      attrs="$attrs\(.values.$a)"
    fi
  done
  filter=""
  if [[ $index != "" ]]; then
    filter='and .index == '"$index"''
  fi
  ensure_tf_json_file
  cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "'"$resource_type"'" and '"$name_filter"' '"$filter"') | "'"$attrs"'"'
}

function format() {
  local fmt_str=$1
  python -c '
import sys
for line in sys.stdin:
  line = line.rstrip()
  if line:
    fields = line.split()
    print(sys.argv[1] % tuple(fields))
' "$fmt_str"
}

function nth_instances() {
  local instance_type=$1
  local instance_index=${2:-}
  local prefix=cdp
  if [[ $instance_type == "ecs" ]]; then
    prefix=ecs
  fi
  ensure_tf_json_file
  if [[ -s $TF_JSON_FILE ]]; then
    if [[ ${TF_VAR_cloud_provider:-} == "aws" ]]; then
      for index in $(get_resource_attr aws_instance ${instance_type} .index ${instance_index:-}); do
        local is_stoppable=$([[ $(get_resource_attr aws_eip eip_${instance_type} .address $index | wc -l) -eq 0 ]] && echo No || echo Yes)
        get_resource_attr aws_instance ${instance_type} ".index tags.Name public_ip public_ip private_ip instance_type id .type .name .index" $index | format "%s %s $prefix.%s.nip.io %s %s %s %s $is_stoppable %s.%s[%s]"
      done
    elif [[ ${TF_VAR_cloud_provider:-} == "azure" ]]; then
      for index in $(get_resource_attr azurerm_virtual_machine ${instance_type} .index ${instance_index:-}); do
        public_ip=$(get_resource_attr azurerm_public_ip ip_${instance_type} ip_address $index)
        private_ip=$(get_resource_attr azurerm_network_interface nic_${instance_type} private_ip_address $index)
        get_resource_attr azurerm_virtual_machine ${instance_type} ".index name vm_size id .type .name .index" $index | format "%s %s $prefix.$public_ip.nip.io $public_ip $private_ip %s %s Yes %s.%s[%s]"
      done
    fi
  fi
}

function cluster_instances() {
  local instance_index=${1:-}
  nth_instances cluster "$instance_index"
}

function ecs_instances() {
  local instance_index=${1:-}
  nth_instances ecs "$instance_index"
}

function ipa_instance() {
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    if [[ ${TF_VAR_cloud_provider:-} == "aws" ]]; then
      local is_stoppable=$([[ $(get_resource_attr aws_eip eip_ipa .address | wc -l) -eq 0 ]] && echo No || echo Yes)
      get_resource_attr aws_instance ipa "tags.Name public_ip public_ip private_ip instance_type id .type .name" | format "%s cdp.%s.nip.io %s %s %s %s $is_stoppable %s.%s"
    elif [[ ${TF_VAR_cloud_provider:-} == "azure" ]]; then
      public_ip=$(get_resource_attr azurerm_public_ip ip_ipa ip_address)
      private_ip=$(get_resource_attr azurerm_network_interface nic_ipa private_ip_address)
      get_resource_attr azurerm_virtual_machine ipa "name vm_size id .type .name" | format "%s cdp.$public_ip.nip.io $public_ip $private_ip %s %s Yes %s.%s"
    fi
  fi
}

function web_instance() {
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    if [[ ${TF_VAR_cloud_provider:-} == "aws" ]]; then
      local is_stoppable=$([[ $(get_resource_attr aws_eip eip_web .address | wc -l) -eq 0 ]] && echo No || echo Yes)
      get_resource_attr aws_instance web "tags.Name public_ip public_ip private_ip instance_type id .type .name" | format "%s cdp.%s.nip.io %s %s %s %s $is_stoppable %s.%s"
    elif [[ ${TF_VAR_cloud_provider:-} == "azure" ]]; then
      public_ip=$(get_resource_attr azurerm_public_ip ip_web ip_address)
      private_ip=$(get_resource_attr azurerm_network_interface nic_web private_ip_address)
      get_resource_attr azurerm_virtual_machine web "name vm_size id .type .name" | format "%s cdp.$public_ip.nip.io $public_ip $private_ip %s %s Yes %s.%s"
    fi
  fi
}

function cluster_attr() {
  local format='$0'
  if [[ $# -gt 0 ]]; then
    local format=""
    for attr in "$@"; do
      if [[ $format != "" ]]; then
        format="$format"\"" "\"""
      fi
      local pos=0
      case "$attr" in
        "index") pos=1 ;;
        "name") pos=2 ;;
        "public_dns") pos=3 ;;
        "public_ip") pos=4 ;;
        "private_ip") pos=5 ;;
        "instance_type") pos=6 ;;
        "id") pos=7 ;;
        "is_stoppable") pos=8 ;;
        "long_id") pos=9 ;;
      esac
      format="$format"'$'"$pos"
    done
  fi
  awk '{print '"$format"'}'
}

function ecs_attr() {
  cluster_attr "$@"
}

function web_attr() {
  local format='$0'
  if [[ $# -gt 0 ]]; then
    local format=""
    for attr in "$@"; do
      if [[ $format != "" ]]; then
        format="$format"\"" "\"""
      fi
      local pos=0
      case "$attr" in
        "name") pos=1 ;;
        "public_dns") pos=2 ;;
        "public_ip") pos=3 ;;
        "private_ip") pos=4 ;;
        "instance_type") pos=5 ;;
        "id") pos=6 ;;
        "is_stoppable") pos=7 ;;
        "long_id") pos=8 ;;
      esac
      format="$format"'$'"$pos"
    done
  fi
  awk '{print '"$format"'}'
}

function ipa_attr() {
  web_attr "$@"
}

#function is_stoppable() {
#  local vm_type=$1
#  local index=$2
#  ensure_tf_json_file
#  if [ -s $TF_JSON_FILE ]; then
#    local count=$(cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_eip" and .name == "eip_'"$vm_type"'" and .index == '"$index"').address' | wc -l)
#    if [[ $count -eq 0 ]]; then
#      echo No
#    else
#      echo Yes
#    fi
#  fi
#}

function enddate() {
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    jq -r '.values.root_module.resources[]? | select(.type == "aws_instance").values.tags.enddate' $TF_JSON_FILE | \
      grep -v null | \
      sed -E 's/^(....)(....)$/\2\1/' | \
      sort -u | \
      head -1 | \
      sed -E 's/^(....)(....)$/\2\1/'
  fi
}

function security_groups() {
  local sg_type=${1:-}
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    local filter=""
    if [[ $sg_type != "" ]]; then
      filter='select(.name == "workshop_'"$sg_type"'_sg") |'
    fi
    jq -r '.values.root_module.resources[]? | '"$filter"' select(.type == "aws_security_group").values.id' $TF_JSON_FILE
  fi
}

#
# Registration code
#

function ensure_registration_code() {
  local code="${1:-}"
  if [[ $code != "" ]]; then
    export TF_VAR_registration_code="$code"
  elif [[ ${TF_VAR_registration_code:-} == "" ]]; then
    result=$(curl -w "%{http_code}" --connect-timeout 5 "https://frightanic.com/goodies_content/docker-names.php" 2>/dev/null)
    status_code=$(echo "$result" | tail -1)
    suggestion=$(echo "$result" | head -1)
    if [[ $status_code != "200" ]]; then
      suggestion="edge2ai-$RANDOM"
    fi
    cat <<EOF | python -c 'import sys; sys.stdout.write(sys.stdin.read().rstrip())'
${C_YELLOW}
Users need a registration code to connect to the Web Server for the first time.
Press ENTER to accept the suggestion below or type an alternative code of your choice.

Alternatively, you can set the TF_VAR_registration_code variable in your .env file to avoid this prompt.
You can reset the registration code at any time by running: ./update-registration-code.sh <namespace> <new_registration_code>

Registration code: [$suggestion] ${C_NORMAL}
EOF
    local confirmation
    read confirmation
    if [[ $confirmation == "" ]]; then
      TF_VAR_registration_code="$suggestion"
    else
      TF_VAR_registration_code="$confirmation"
    fi
    export TF_VAR_registration_code
  fi
  mkdir -p "$(dirname $REGISTRATION_CODE_FILE)"
  echo -n "$TF_VAR_registration_code" > $REGISTRATION_CODE_FILE
}

function registration_code() {
  if [[ -s $REGISTRATION_CODE_FILE ]]; then
    cat $REGISTRATION_CODE_FILE
  else
    echo "<not set>"
  fi
}

#
# Web Server API
#

function get_ips() {
  local web_ip_address=${1:-$( web_instance | web_attr public_ip )}
  local admin_email=${2:-$TF_VAR_web_server_admin_email}
  local admin_pwd=${3:-$TF_VAR_web_server_admin_password}
  curl -k -H "Content-Type: application/json" -X GET \
    -u "${admin_email}:${admin_pwd}" \
    "http://${web_ip_address}/api/ips" 2>/dev/null | \
  jq -r '.ips[]'
}

function update_web_server() {
  local attr=$1
  local value=$2
  local sensitive=${3:-false}
  local web_ip_address=${4:-$(web_instance | web_attr public_ip)}
  local admin_email=${5:-$TF_VAR_web_server_admin_email}
  local admin_pwd=${6:-$TF_VAR_web_server_admin_password}
  
  sensitive=$(echo "$sensitive" | tr "A-Z" "a-z")
  if [[ $sensitive != "true" && $sensitive != "false" ]]; then
    echo "${C_RED}ERROR: sensitive must be either true or false.${C_NORMAL}"
    abort
  fi
  wait_for_web "$web_ip_address"
  
  # Set registration code
  curl -k -H "Content-Type: application/json" -X POST \
    -u "${admin_email}:${admin_pwd}" \
    -d '{
         "attr":"'"$attr"'",
         "value": "'"$value"'",
         "sensitive": '"$sensitive"'
        }' \
    "http://${web_ip_address}/api/config" 2>/dev/null
}

function service_url() {
  local service_id=$1
  grep -o "${service_id}=[^=,]*=[^=,]*" | sed 's/.*=//'
}

function url_for_ip() {
  local url=$1
  local ip=$2
  local host="cdp.$ip.nip.io"
  echo "$url" | sed "s/{host}/$host/;s/{ip_address}/$ip/"
}

#
# Helper functions
#

function calc() {
  local expression=$1
  echo "$expression" | bc -l
}

function yamlize() {
  python -c 'import json, yaml, sys; print(yaml.dump(json.loads(sys.stdin.read())))'
}

function timeout() {
  local timeout_secs=$1
  local cmd=$2
  python -c "import subprocess, sys; r = subprocess.run(sys.argv[2], shell=True, timeout=int(sys.argv[1])); exit(r.returncode)" "$timeout_secs" "$cmd" 2>&1 | (grep -v LC_CTYPE || true)
}

#
# Cleanup functions
#

function cleanup() {
  # placeholder
  true
}

function _cleanup() {
  local sig=$1
  local ret=$2
  reset_traps

  if [[ $PUBLIC_IPS_FILE != "" && -f $PUBLIC_IPS_FILE ]]; then
    rm -f $PUBLIC_IPS_FILE
  fi

  LC_ALL=C type cleanup 2>&1 | egrep -q "is a (shell )*function" && (cleanup || true)

  if [[ $ret -ne 0 ]]; then
    echo -e "\n   FAILED!!! (signal: $sig, exit code: $ret)\n"
  fi
}

function set_traps() {
  local sig=0
  for sig in {0..16} {18..27} {29..31}; do
    trap '_cleanup '$sig' $?' $sig
  done
}

function reset_traps() {
  local sig=0
  for sig in {0..16} {18..27} {29..31}; do
    trap - $sig
  done
}

if [[ ${DEBUG:-} != "" ]]; then
  set -x
fi

#
# MAIN
#

ARGS=("$@")
# Clean old ip address files
find $BASE_DIR -name ".hosts.*" -mmin +15 -delete 2>/dev/null
# Caffeine check must be first
check_for_caffeine "$@"
ensure_ulimit
if [[ ${NAMESPACE:-} != "" ]]; then
  load_env $NAMESPACE # Must happen before docker invocation to allow for interactive cloud login
fi
maybe_launch_docker "${ARGS[@]:-}"
check_python_modules
check_for_jq
set_traps
