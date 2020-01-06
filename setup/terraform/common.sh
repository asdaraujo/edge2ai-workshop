#!/bin/bash

function log() {
  echo "[$(date)] [$(basename $0): $BASH_LINENO] : $*"
}

function check_env_files() {
  if [ -f $BASE_DIR/.env.default ]; then
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

function show_namespaces() {
  check_env_files

  local namespaces=$(ls -1d $BASE_DIR/.env* | egrep "/\.env($|\.)" | fgrep -v .env.template | \
                       sed 's/\.env\.//;s/\/\.env$/\/default/')
  if [ "$namespaces" == "" ]; then
    echo -e "\n  No namespaces are currently defined!\n"
  else
    echo -e "\nNamespaces:"
    for namespace in $namespaces; do
      echo "  - $(basename $namespace)"
    done
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
  awk '$1 ~ /-'$cluster_number'$/{print $2}' $INSTANCE_LIST_FILE
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

function check_config() {
  local template_file=$1
  local compare_file=$2
  if [ ! -f $template_file ]; then
    echo "ERROR: Cannot find the template file $template_file." > /dev/stderr
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

function check_all_configs() {
  local stack
  check_config $BASE_DIR/.env.template $(get_env_file_path $NAMESPACE)
  if [ -e $BASE_DIR/resources/stack.${NAMESPACE}.sh ]; then
    stack=$BASE_DIR/resources/stack.${NAMESPACE}.sh
  else
    stack=$BASE_DIR/resources/stack.sh
  fi
  check_config $BASE_DIR/resources/stack.template.sh $stack
}

check_for_jq

for sig in {0..31}; do
  trap 'RET=$?; if [ $RET != 0 ]; then echo -e "\n   FAILED!!! (signal: '$sig', exit code: $RET)\n"; fi' $sig
done
