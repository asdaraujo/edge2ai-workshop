#!/bin/bash

export PS4='+ \D{%Y-%m-%d %H:%M:%S} [${BASH_SOURCE#'"$BASE_DIR"/'}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ ${DEBUG:-} != "" ]]; then
  set -x
fi

# Color codes
# Disable xtrace temporarily to avoid color explosion in the output
reset_xtrace=false
if [[ -o xtrace ]]; then
  set +x
  reset_xtrace=true
fi
C_NORMAL="$(echo -e "\033[0m")"
C_BOLD="$(echo -e "\033[1m")"
C_DIM="$(echo -e "\033[2m")"
C_BLACK="$(echo -e "\033[30m")"
C_RED="$(echo -e "\033[31m")"
C_GREEN="$(echo -e "\033[32m")"
C_YELLOW="$(echo -e "\033[33m")"
C_BLUE="$(echo -e "\033[34m")"
C_WHITE="$(echo -e "\033[97m")"
C_BG_GREEN="$(echo -e "\033[42m")"
C_BG_RED="$(echo -e "\033[101m")"
C_BG_MAGENTA="$(echo -e "\033[105m")"
"$reset_xtrace" && set -x

function log() {
  echo "[$(date)] [$(basename $0): $BASH_LINENO] : $*"
}

function error() {
  echo "${C_RED}ERROR: $*${C_NORMAL}" >&2
}

function abort() {
  echo "Aborting."
  exit 1
}

function check_env_files() {
  if [[ -f $BASE_DIR/.env.default ]]; then
    echo 'ERROR: An enviroment file cannot be called ".env.default". Please renamed it to ".env".'
    abort
  fi
}

function get_namespaces() {
    ls -1d $BASE_DIR/.env* | egrep "/\.env($|\.)" | fgrep -v .env.template | \
    sed 's/\.env\.//;s/\/\.env$/\/default/' | xargs -I{} basename {}
}

function get_namespace_instances() {
  local namespace=$1
  local tf_json="${BASE_DIR}/namespaces/${namespace}/${namespace}.tf.json"
  if [[ -s $tf_json ]]; then
    set +e
    local instances
    instances=$(jq -r '.values.root_module.resources[] | select(.type == "aws_instance") | "\(if .name == "cluster" then .index else .name end)"' "$tf_json" 2>/dev/null | sort | tr "\n" "," | sed 's/,$//;s/,/, /g')
    local ret=$?
    set -e
    if [[ $ret -eq 0 ]]; then
      echo "$instances"
    fi
  fi
}

function show_namespaces() {
  check_env_files

  local namespaces=$(get_namespaces)
  if [ "$namespaces" == "" ]; then
    echo -e "\n  No namespaces are currently defined!\n"
  else
    echo -e "\nNamespaces:"
    for namespace in $namespaces; do
      local instances=$(get_namespace_instances "$namespace")
      if [[ $instances == "" ]]; then
        echo "  - $namespace"
      else
        printf "%-25s %s\n" "  - $namespace" "(instances: $instances)"
      fi
    done
  fi
}
