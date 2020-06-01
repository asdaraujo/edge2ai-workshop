#!/bin/bash

DEFAULT_DOCKER_IMAGE=asdaraujo/edge2ai-workshop:latest
GITHUB_REPO=asdaraujo/edge2ai-workshop
GITHUB_BRANCH=master

BUILD_FILE=.build
STACK_BUILD_FILE=.stack.build
LAST_STACK_CHECK_FILE=$BASE_DIR/.last.stack.build.check

# Color codes
C_NORMAL="$(echo -e "\033[0m")"
C_BOLD="$(echo -e "\033[1m")"
C_DIM="$(echo -e "\033[2m")"
C_RED="$(echo -e "\033[31m")"
C_YELLOW="$(echo -e "\033[33m")"

function log() {
  echo "[$(date)] [$(basename $0): $BASH_LINENO] : $*"
}

function check_version() {
  if [[ ! -f $BASE_DIR/NO_VERSION_CHECK ]]; then

    # First, try automated refresh using git

    if [[ $(which git 2>/dev/null) ]]; then
      #
      mkdir -p ~/.ssh
      ssh-keyscan "github.com" >> ~/.ssh/known_hosts 2>/dev/null
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
        echo "   https://github.com/$GITHUB_REPO/"
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

function _find_docker_image() {
  local img_candidates=($DEFAULT_DOCKER_IMAGE edge2ai-workshop:latest)
  if [ "${EDGE2AI_DOCKER_IMAGE:-}" != "" ]; then
    img_candidates=(${EDGE2AI_DOCKER_IMAGE})
  fi
  for img in "${img_candidates[@]}"; do
    local label=${img%%:*}
    local tag
    if [[ $img == *":"* ]]; then
      tag=${img##*:}
    else
      tag=latest
    fi
    local has_docker_img=$(docker image ls 2> /dev/null | awk '$1 == "'"$label"'" && $2 == "'"$tag"'"' | wc -l)
    if [ "$has_docker_img" -eq "1" ]; then
      echo "${label}:${tag}"
      return
    fi
  done
}

function check_docker_launch() {
  local is_inside_docker=$(egrep "/(lxc|docker)/" /proc/1/cgroup > /dev/null 2>&1 && echo yes || echo no)
  if [ "${NO_DOCKER:-}" == "" -a "$is_inside_docker" == "no" ]; then
    docker_img=$(_find_docker_image)
    if [ "$docker_img" != "" ]; then
      local cmd=./$(basename $0)
      echo -e "${C_DIM}Using docker image: ${docker_img}${C_NORMAL}"
      exec docker run -ti --rm --entrypoint="" -v $BASE_DIR/../..:/edge2ai-workshop $docker_img $cmd $*
    fi
  fi
  if [ "${EDGE2AI_DOCKER_IMAGE:-}" != "" ]; then
    echo "ERROR: Docker image [$EDGE2AI_DOCKER_IMAGE] does not exist. Please check your EDGE2AI_DOCKER_IMAGE env variable."
    exit
  fi
  if [ "$is_inside_docker" == "no" ]; then
    echo -e "${C_DIM}Running locally (no docker)${C_NORMAL}"
  fi
}

function check_env_files() {
  if [[ -f $BASE_DIR/.env.default ]]; then
    echo 'ERROR: An enviroment file cannot be called ".env.default". Please renamed it to ".env".'
    exit 1
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

  if [ ! -f $env_file ]; then
    echo ""
    echo "The namespace [$namespace] has not been configured."
    echo "1. Create the environment by copying the environment template:"
    echo "     cp .env.template .env.<namespace_name>"
    echo "2. Review and configure .env.<namespace_name> appropriately."
    echo ""
    exit 1
  fi
  source $env_file
  export NAMESPACE=$namespace
  NAMESPACE_DIR=$BASE_DIR/namespaces/$namespace
  INSTANCE_LIST_FILE=$NAMESPACE_DIR/.instance.list
  WEB_INSTANCE_LIST_FILE=$NAMESPACE_DIR/.instance.web
  export TF_VAR_namespace=$NAMESPACE
  export TF_VAR_name_prefix=$(echo "$namespace" | tr "A-Z" "a-z")
  export TF_VAR_key_name="${TF_VAR_name_prefix}-$(echo -n "$TF_VAR_owner" | base64)"
  export TF_VAR_web_key_name="${TF_VAR_name_prefix}-$(echo -n "$TF_VAR_owner" | base64)-web"

  export TF_VAR_ssh_private_key=$NAMESPACE_DIR/${TF_VAR_key_name}.pem
  export TF_VAR_ssh_public_key=$NAMESPACE_DIR/${TF_VAR_key_name}.pem.pub
  export TF_VAR_web_ssh_private_key=$NAMESPACE_DIR/${TF_VAR_web_key_name}.pem
  export TF_VAR_web_ssh_public_key=$NAMESPACE_DIR/${TF_VAR_web_key_name}.pem.pub
  export TF_VAR_my_public_ip=$(curl -sL ifconfig.me || curl -sL ipapi.co/ip || curl -sL icanhazip.com)
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

function ensure_instance_list() {
  if [ ! -s $INSTANCE_LIST_FILE ]; then
    $BASE_DIR/list-details.sh $NAMESPACE > /dev/null
  fi
}

function public_dns() {
  local cluster_number=$1
  ensure_instance_list $NAMESPACE
  if [ "$cluster_number" == "web" ]; then
    awk '{print $2}' $WEB_INSTANCE_LIST_FILE
  else
    awk '$1 ~ /-'$cluster_number'$/{print $2}' $INSTANCE_LIST_FILE
  fi
}

function public_ip() {
  local cluster_number=$1
  ensure_instance_list $NAMESPACE
  awk '$1 ~ /-'$cluster_number'$/{print $3}' $INSTANCE_LIST_FILE
}

function private_ip() {
  local cluster_number=$1
  ensure_instance_list $NAMESPACE
  awk '$1 ~ /-'$cluster_number'$/{print $4}' $INSTANCE_LIST_FILE
}

function check_for_jq() {
  set +e
  jq --version > /dev/null 2>&1
  RET=$?
  set -e
  if [ $RET != 0 ]; then
    echo "ERROR: The "jq" tool is not installed and it is required."
    echo "       Please install jq and try again. Check the documentation for"
    echo "       more details."
    exit 1
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
      echo "ERROR: Configuration file $compare is missing property ${var}." > /dev/stderr
      stale=1
    fi
  done
  not_set=$(grep -E "^ *(export){0,1} *[a-zA-Z0-9_]*=" $compare | sed -E 's/ *(export){0,1} *//;s/="?<[A-Z_]*>"?$/=/g;s/""//g' | egrep "CHANGE_ME|REPLACE_ME|=$" | sed 's/=//' | tr "\n" "," | sed 's/,$//')
  if [ "$not_set" != "" ]; then
    echo "ERROR: Configuration file $compare has the following unset properties: ${not_set}." > /dev/stderr
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
    echo "${C_RED}ERROR: The specified enviroment file ($compare_file) does not exist.${C_NORMAL}" > /dev/stderr
    exit 1
  fi
  if [ ! -f $template_file ]; then
    echo "${C_RED}ERROR: Cannot find the template file $template_file.${C_NORMAL}" > /dev/stderr
    exit 1
  fi
  if [ "$(check_file_staleness $template_file $compare_file)" != "0" ]; then
      cat > /dev/stderr <<EOF

ERROR: Please fix the problems above in the file $compare_file and try again.
       If this configuration was working before, you may have upgraded to a new version
       of the workshop that requires additional properties.
       You can refer to the template $template_file for a list of all the required properties.
EOF
      exit 1
  fi
}

function kerb_auth_for_cluster() {
  local cluster_id=$1
  local public_dns=$(public_dns $cluster_id)
  if [ "$ENABLE_KERBEROS" == "yes" ]; then
    export KRB5_CONFIG=$NAMESPACE_DIR/krb5.conf.$cluster_id
    scp -q -o StrictHostKeyChecking=no -i $TF_VAR_ssh_private_key $TF_VAR_ssh_username@$public_dns:/etc/krb5.conf $KRB5_CONFIG
    sed -i.bak "s/kdc *=.*internal/kdc = $public_dns/;s/admin_server *=.*internal/admin_server = $public_dns/;/includedir/ d" $KRB5_CONFIG
    export KRB5CCNAME=/tmp/workshop.$$
    echo supersecret1 | kinit workshop 2>&1 | grep -v "Password for" | true
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

function set_traps() {
  for sig in {0..16} {18..31}; do
    trap 'RET=$?; reset_traps; if [ $RET != 0 ]; then echo -e "\n   FAILED!!! (signal: '$sig', exit code: $RET)\n"; fi; set +e; kdestroy > /dev/null 2>&1' $sig
  done
}

function reset_traps() {
  for sig in {0..16} {18..31}; do
    trap - $sig
  done
}

ARGS=("$@")
ensure_ulimit
check_docker_launch "${ARGS[@]:-}"
check_for_jq
set_traps
