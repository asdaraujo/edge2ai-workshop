#!/bin/bash

# Often yum connection to Cloudera repo fails and causes the instance create to fail.
# yum timeout and retries options don't see to help in this type of failure.
# We explicitly retry a few times to make sure the build continues when these timeouts happen.
function yum_install() {
  local packages=$@
  local retries=10
  while true; do
    set +e
    yum install -d1 -y ${packages}
    RET=$?
    set -e
    if [[ ${RET} == 0 ]]; then
      break
    fi
    retries=$((retries - 1))
    if [[ ${retries} -lt 0 ]]; then
      echo 'YUM install failed!'
      exit 1
    else
      echo 'Retrying YUM...'
    fi
  done
}

function get_homedir() {
  local username=$1
  getent passwd $username | cut -d: -f6
}

function load_stack() {
  local namespace=$1
  local base_dir=${2:-$BASE_DIR}
  if [ -e $base_dir/stack.${namespace}.sh ]; then
    source $base_dir/stack.${namespace}.sh
  else
    source $base_dir/stack.sh
  fi
  export CM_SERVICES=$CM_SERVICES
  export CM_SERVICES=$(echo "$CM_SERVICES" | tr "[a-z]" "[A-Z]")
  export CM_VERSION CDH_VERSION CDH_BUILD CDH_PARCEL_REPO ANACONDA_VERSION ANACONDA_PARCEL_REPO
  export ANACONDA_VERSION CDH_BUILD CDH_PARCEL_REPO CDH_VERSION CDSW_PARCEL_REPO CDSW_BUILD
  export CFM_PARCEL_REPO CFM_VERSION CM_VERSION CSA_PARCEL_REPO CSP_PARCEL_REPO FLINK_BUILD
  export SCHEMAREGISTRY_BUILD STREAMS_MESSAGING_MANAGER_BUILD
}
