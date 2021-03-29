#!/bin/bash

export PS4='+ [${BASH_SOURCE#'"$BASE_DIR"/'}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

DOCKER_REPO=asdaraujo/edge2ai-workshop
DEFAULT_DOCKER_IMAGE=${DOCKER_REPO}:latest
GITHUB_FQDN="github.com"
GITHUB_REPO=cloudera-labs/edge2ai-workshop
GITHUB_BRANCH=master

BUILD_FILE=.build
STACK_BUILD_FILE=.stack.build
LAST_STACK_CHECK_FILE=$BASE_DIR/.last.stack.build.check
PUBLIC_IPS_FILE=$BASE_DIR/.hosts.$$

THE_PWD=supersecret1

# Color codes
C_NORMAL="$(echo -e "\033[0m")"
C_BOLD="$(echo -e "\033[1m")"
C_DIM="$(echo -e "\033[2m")"
C_RED="$(echo -e "\033[31m")"
C_YELLOW="$(echo -e "\033[33m")"
C_BLUE="$(echo -e "\033[34m")"
C_WHITE="$(echo -e "\033[97m")"
C_BG_RED="$(echo -e "\033[101m")"
C_BG_MAGENTA="$(echo -e "\033[105m")"

OPTIONAL_VARS="TF_VAR_registration_code"

function log() {
  echo "[$(date)] [$(basename $0): $BASH_LINENO] : $*"
}

function abort() {
  echo "Aborting."
  exit 1
}

function check_version() {
  if [[ ! -f $BASE_DIR/NO_VERSION_CHECK ]]; then

    # First, try automated refresh using git

    if [[ $(which git 2>/dev/null) ]]; then
      #
      mkdir -p ~/.ssh
      set -o pipefail
      ssh-keyscan "$GITHUB_FQDN" 2>&1 | (egrep -v "${GITHUB_FQDN}:22|${GITHUB_FQDN} *ssh-rsa" || true) || (echo "ERROR: Docker is unable to resolve the IP for ${GITHUB_FQDN}"; false)
      set +o pipefail
      # git is installed
      remote=$(git status | grep "Your branch" | egrep -o "[^']*/${GITHUB_BRANCH}\>" | sed 's#/.*##')
      if [[ $remote != "" ]]; then
        # current branch points to the remote $GITHUB_BRANCH branch
        uri=$(git remote -v | egrep "^ *$remote\s.*\(fetch\)" | awk '{print $2}')
        if [[ $uri =~ "$GITHUB_REPO" ]]; then
          # remote repo is the official repo
          git fetch > /dev/null 2>&1 || true
          if [[ $(git status) =~ "Your branch is up to date" ]]; then
            echo "edge2ai-workshop repo is up to date."
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
    last_stack_check=$(head -1 $LAST_STACK_CHECK_FILE 2>/dev/null | grep -o "^[0-9]\{14\}" | head -1)
    latest_stack=$(curl "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/$STACK_BUILD_FILE" 2>/dev/null | head -1 | grep -o "^[0-9]\{14\}" | head -1)
    echo "$latest_stack" > $LAST_STACK_CHECK_FILE
    if [[ $latest_stack != "" ]]; then
      if [[ $last_stack_check == "" || $last_stack_check < $latest_stack ]]; then
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
  local image_id=$(docker inspect $DEFAULT_DOCKER_IMAGE | jq -r '.[].Id')
  local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${DOCKER_REPO}:pull" | jq -r .token)
  local latest_image_id=$(curl -s -H "Authorization: Bearer $token" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "https://index.docker.io/v2/${DOCKER_REPO}/manifests/latest" | jq -r '.config.digest')
  if [[ $image_id != $latest_image_id ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

function check_docker_launch() {
  if [[ "${NO_DOCKER:-}" == "" && "${NO_DOCKER_EXEC:-}" == "" && "$(is_docker_running)" == "yes" ]]; then
    create_ips_file

    local docker_img=${EDGE2AI_DOCKER_IMAGE:-$DEFAULT_DOCKER_IMAGE}
    if [[ ${NO_DOCKER_MSG:-} == "" ]]; then
      echo -e "${C_DIM}Using docker image: ${docker_img}${C_NORMAL}"
      export NO_DOCKER_MSG=1
    fi
    if [[ "${NO_DOCKER_PULL:-}" == "" && $docker_img == $DEFAULT_DOCKER_IMAGE ]]; then
      if [[ $(is_docker_image_stale) == "yes" ]]; then
        docker pull $docker_img || true
      fi
    fi

    local cmd=./$(basename $0)
    exec docker run -ti --rm \
      --detach-keys="ctrl-@" \
      --entrypoint="" \
      -v $BASE_DIR/../..:/edge2ai-workshop \
      -e HOSTS_ADD=$(basename $PUBLIC_IPS_FILE) \
      $docker_img \
      $cmd $*
  fi
  local is_inside_docker=$(egrep "/(lxc|docker)/" /proc/1/cgroup > /dev/null 2>&1 && echo yes || echo no)
  if [[ "$is_inside_docker" == "no" ]]; then
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
    exec docker run --rm \
      --entrypoint="" \
      -v $BASE_DIR/../..:/edge2ai-workshop \
      $docker_img \
      /bin/bash -c "cd /edge2ai-workshop/setup/terraform; export BASE_DIR=\$PWD; source common.sh; load_env $namespace; ${cmd[@]}"
  else
    (load_env $namespace; "${cmd[@]}")
  fi
}

function check_env_files() {
  if [[ -f $BASE_DIR/.env.default ]]; then
    echo 'ERROR: An enviroment file cannot be called ".env.default". Please renamed it to ".env".'
    abort
  fi
}

function check_python_modules() {
  python -c '
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
  NAMESPACE_DIR=$BASE_DIR/namespaces/$namespace
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
  export TF_VAR_my_public_ip=$(curl -sL ifconfig.me || curl -sL ipapi.co/ip || curl -sL icanhazip.com)

  export AWS_ACCESS_KEY_ID=$TF_VAR_aws_access_key_id
  export AWS_SECRET_ACCESS_KEY=$TF_VAR_aws_secret_access_key
  export AWS_DEFAULT_REGION=$TF_VAR_aws_region

  TF_VAR_use_elastic_ip=$(echo "${TF_VAR_use_elastic_ip:-FALSE}" | tr A-Z a-z)
  if [ "$TF_VAR_use_elastic_ip" == "yes" -o "$TF_VAR_use_elastic_ip" == "true" -o "$TF_VAR_use_elastic_ip" == "1" ]; then
    TF_VAR_use_elastic_ip=true
  else
    TF_VAR_use_elastic_ip=false
  fi
  export TF_VAR_use_elastic_ip

}

function run_terraform() {
  local args=("$@")
  check_terraform_version
  $TERRAFORM "${args[@]}"
}

function check_terraform_version() {
  # if there's a remnant of a state file, ensures it matches the Terraform version
  local state_version="*"
  if [[ -f $TF_STATE ]]; then
    # if the state file is empty of resource, just remove it and start fresh
    if [[ $(jq '.resources[]' $TF_STATE) == "" ]]; then
      rm -f $TF_STATE ${TF_STATE}.backup
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
  exit 1
}

function get_namespaces() {
    ls -1d $BASE_DIR/.env* | egrep "/\.env($|\.)" | fgrep -v .env.template | \
    sed 's/\.env\.//;s/\/\.env$/\/default/' | xargs -I{} basename {}
}

function show_namespaces() {
  check_env_files

  local namespaces=$(get_namespaces)
  if [ "$namespaces" == "" ]; then
    echo -e "\n  No namespaces are currently defined!\n"
  else
    echo -e "\nNamespaces:"
    for namespace in $namespaces; do
      echo "  - $namespace"
    done
  fi
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
      AWS_DEFAULT_REGION=$TF_VAR_aws_region \
      AWS_ACCESS_KEY_ID=$TF_VAR_aws_access_key_id \
      AWS_SECRET_ACCESS_KEY=$TF_VAR_aws_secret_access_key \
        aws ec2 describe-key-pairs \
          --filters '[{"Name": "key-name","Values":["'"${TF_VAR_key_name}"'","'"${TF_VAR_web_key_name}"'"]}]' | \
        jq -r '.KeyPairs[].KeyName' | tr '\n' ',' | sed 's/,$//'
}

function aws_delete_key_pairs() {
  local keys=$1
  for key_name in $(echo "$keys" | sed 's/,/ /g'); do
    echo "Deleting key pair [$key_name]"
    AWS_DEFAULT_REGION=$TF_VAR_aws_region \
    AWS_ACCESS_KEY_ID=$TF_VAR_aws_access_key_id \
    AWS_SECRET_ACCESS_KEY=$TF_VAR_aws_secret_access_key \
      aws ec2 delete-key-pair --key-name "$key_name"
  done
}

function check_for_orphaned_keys() {
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
  else
    echo "there's a deployment"
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
  local cluster_number=$1
  if [ "$cluster_number" == "web" ]; then
    web_instance | web_attr public_dns
  else
    cluster_instances $cluster_number | cluster_attr public_dns
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
    fi
  done
  if [ "$ret" == "200" ]; then
    echo "Web server is ready!"
  else
    echo "ERROR: Web server didn't respond successfully."
    return 1
  fi
}

function collect_logs() {
  local namespace=$1
  if [[ $namespace == "" ]]; then
    return
  fi
  if [[ $0 != *"/launch.sh" ]]; then
    return
  fi
  did_terraform_run=$(grep "Launching Terraform" $LOG_NAME | wc -l || true)
  no_run=$(grep "^Aborting." $LOG_NAME | wc -l || true)
  if [[ $no_run -gt 0 || $did_terraform_run -eq 0 ]]; then
    return
  fi
  success=$(grep "Deployment completed successfully" $LOG_NAME | wc -l || true)
  if [[ $success -eq 1 ]]; then
    return
  fi
  load_env "$namespace"
  local tmp_file=/tmp/list-details.$$
  local log_name=""
  set +e
  $BASE_DIR/list-details.sh "$namespace" > $tmp_file 2>/dev/null
  echo "Collecting logs:"
  grep "${namespace}-web" $tmp_file | awk '{print $2}' | while read host_name; do
    log_name=${LOG_NAME}.web
    scp -q -o StrictHostKeyChecking=no -i "$TF_VAR_web_ssh_private_key" $TF_VAR_ssh_username@$host_name:./web/start-web.log "$log_name"
    if [[ $? == 0 ]]; then
      echo "  Saved log from web server as $log_name"
    else
      echo "  ERROR: Could not download log web/start-web.log from the web server"
    fi
  done
  idx=0
  grep "${namespace}-cluster" $tmp_file | awk '{print $2}' | while read host_name; do
    log_name=${LOG_NAME}.cluster-$idx
    scp -q -o StrictHostKeyChecking=no -i "$TF_VAR_ssh_private_key" $TF_VAR_ssh_username@$host_name:/tmp/resources/setup.log ${LOG_NAME}.cluster-$idx
    if [[ $? == 0 ]]; then
      echo "  Saved log from cluster-$idx server as $log_name"
    else
      echo "  ERROR: Could not download log /tmp/resources/setup.log from the cluster-$idx server"
    fi
    idx=$((idx+1))
  done
  rm -f $tmp_file
}

#
# AWS EC2 functions
#

function add_ingress() {
  local group_id=$1
  local cidr=$2
  local protocol=$3
  local port=${4:-}
  local description=${5:-default}
  local force=${6:-}

  local tmp_file=/tmp/add-ingress.$$

  ingress=$(get_ingress "$group_id" "$cidr" "$protocol" "$port")
  if [[ $ingress == "" || $force == "force" ]]; then
    local port_option=""
    local proto=$protocol
    if [[ $protocol == "all" ]]; then
       proto=-1
    else
      if [[ $port == "" ]]; then
        echo "ERROR: Port is required for protocol $protocol"
        exit 1
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
    cmd=(aws ec2 authorize-security-group-ingress --group-id "$group_id" --ip-permissions "IpProtocol=${proto},${port_option}IpRanges=[{CidrIp=${cidr},Description=${description}}]")

    msg="  Granting access on ${group_id}:${protocol}:${port} to ${cidr} $([[ $description == "" ]] || echo "($description)") $([[ $force == "force" ]] && echo " - (forced)" || true)"
    set +e
    "${cmd[@]}" > $tmp_file 2>&1
    local ret=$?
    if [[ $ret -eq 0 ]]; then
      echo "$msg"
    elif [[ $(grep -c "the specified rule .* already exists" $tmp_file) -ne 1 ]]; then
      echo "$msg"
      cat $tmp_file
      rm -f $tmp_file
      exit $ret
    fi
    rm -f $tmp_file
    set -e
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
    local port_option=""
    if [[ $protocol != "all" ]]; then
      if [[ $port == "" ]]; then
        echo "ERROR: Port is required for protocol $protocol"
        exit 1
      fi
      port_option="--port ${port}"
    fi
    cmd=(aws ec2 revoke-security-group-ingress --group-id $group_id --protocol $protocol --cidr $cidr $port_option)
    msg="  Revoking access on ${group_id}:${protocol}:${port} from ${cidr} $([[ $force == "force" ]] && echo "(forced)" || true)"
    set +e
    "${cmd[@]}" > $tmp_file 2>&1
    local ret=$?
    if [[ $ret -eq 0 ]]; then
      echo "$msg"
    elif [[ $ret -ne 0 && $(grep -c "The specified rule does not exist in this security group" $tmp_file) -ne 1 ]]; then
      cat $tmp_file
      rm -f $tmp_file
      exit $ret
    fi
    rm -f $tmp_file
    set -e
  fi
}

#
# Terraform refresh and parsing functions
#

function refresh_tf() {
  echo "${C_DIM}Refreshing deployment state. Please wait...${C_NORMAL}" >&2
  mkdir -p $NAMESPACE_DIR
  rm -f $TF_JSON_FILE
  (cd $BASE_DIR && \
     run_terraform refresh -state $TF_STATE >/dev/null && \
     run_terraform show -json $TF_STATE > $TF_JSON_FILE)
}

function ensure_tf_json_file() {
  if [[ -s $TF_STATE && ( ! -s $TF_JSON_FILE || $TF_STATE -nt $TF_JSON_FILE ) ]]; then
    refresh_tf
  fi
}

function web_instance() {
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_instance" and .name == "web") | "\(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
  fi
}

function web_attr() {
  local attr=$1
  local pos=0
  case "$attr" in
    "name") pos=1 ;;
    "public_dns") pos=2 ;;
    "public_ip") pos=3 ;;
    "private_ip") pos=4 ;;
  esac
  awk '{print $'$pos'}'
}

function cluster_instances() {
  local cluster_id=${1:-}
  ensure_tf_json_file
  if [[ -s $TF_JSON_FILE ]]; then
    local filter=""
    if [[ $cluster_id != "" ]]; then
      filter='select(.index == '$cluster_id') |'
    fi
    cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_instance" and .name == "cluster") |'"$filter"' "\(.index) \(.values.tags.Name) \(.values.public_dns) \(.values.public_ip) \(.values.private_ip)"'
  fi
}

function cluster_attr() {
  local attr=$1
  local pos=0
  case "$attr" in
    "index") pos=1 ;;
    "name") pos=2 ;;
    "public_dns") pos=3 ;;
    "public_ip") pos=4 ;;
    "private_ip") pos=5 ;;
  esac
  awk '{print $'$pos'}'
}

function is_stoppable() {
  local vm_type=$1
  local index=$2
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    local count=$(cat $TF_JSON_FILE | jq -r '.values[]?.resources[]? | select(.type == "aws_eip" and .name == "eip_'"$vm_type"'" and .index == '"$index"').address' | wc -l)
    if [[ $count -eq 0 ]]; then
      echo No
    else
      echo Yes
    fi
  fi
}

function enddate() {
  ensure_tf_json_file
  if [ -s $TF_JSON_FILE ]; then
    cat $TF_JSON_FILE | jq -r '.values.root_module.resources[0].values.tags.enddate' | sed 's/null//'
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
    jq -r '.values.root_module.resources[] | '"$filter"' select(.type == "aws_security_group").values.id' $TF_JSON_FILE
  fi
}

function get_ingress() {
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
  jq -r '.values.root_module.resources[].values | select(.id == "'"$sg_id"'").ingress[] | '"$protocol_filter"' '"$port_filter"' '"$description_filter"' . as $parent | $parent.cidr_blocks[] | '"$cidr_filter"' "\(.) \(if $parent.protocol == "-1" then "all" else $parent.protocol end) \(if $parent.from_port == $parent.to_port then $parent.from_port else ($parent.from_port|tostring)+"-"+($parent.to_port|tostring) end)"' $TF_JSON_FILE
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
    echo "ERROR: sensitive must be either true or false."
    exit 1
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

#
# Helper functions
#

function calc() {
  local expression=$1
  echo "$expression" | bc -l
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

  LC_ALL=C type cleanup 2>&1 | egrep -q "is a (shell )*function" && (cleanup || true)

  if [[ $ret -ne 0 ]]; then
    echo -e "\n   FAILED!!! (signal: $sig, exit code: $ret)\n"
  fi
}

function set_traps() {
  local sig=0
  for sig in {0..16} {18..31}; do
    trap '_cleanup '$sig' $?' $sig
  done
}

function reset_traps() {
  local sig=0
  for sig in {0..16} {18..31}; do
    trap - $sig
  done
}

ARGS=("$@")
# Caffeine check must be first
check_for_caffeine "$@"
ensure_ulimit
check_docker_launch "${ARGS[@]:-}"
check_for_jq
set_traps
