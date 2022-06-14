#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common-basics.sh

if [[ $# != 1 && $# != 2 ]]; then
  echo "Syntax: $0 <namespace> [start_epoch]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
START_TIME=${2:-$(date +%s)}

source $BASE_DIR/common.sh

CURL=(curl -L -k --connect-timeout 5)
CPIDS=""

STATUS_UNKNOWN="${C_WHITE}?${C_NORMAL}"
STATUS_FETCHING="${C_WHITE}#${C_NORMAL}"
STATUS_COMPLETED="${C_BG_GREEN}${C_BLACK}.${C_NORMAL}"
STATUS_RUNNING="${C_BLUE}r${C_NORMAL}"
STATUS_STALE="${C_YELLOW}R${C_NORMAL}"
STATUS_FAILED="${C_BG_RED}${C_BLACK}X${C_NORMAL}"

function cleanup() {
#  if [[ ${STATUS_FILE_PREFIX:-} != "" ]]; then
#    rm -f "${STATUS_FILE_PREFIX}".*
#  fi
  if [[ ${CPIDS:-} != "" ]]; then
    kill -9 $CPIDS 2>/dev/null
  fi
}

function timeout() {
  local timeout_secs=$1
  local cmd=$2
  python -c "import subprocess, sys; subprocess.run(sys.argv[2], shell=True, timeout=int(sys.argv[1]))" "$timeout_secs" "$cmd" 2>/dev/null
}

function check_instance_status() {
  set -x
  local id=$1
  local ip=$2
  local pvt_key=$TF_VAR_ssh_private_key
  local cmd="bash /tmp/resources/check-setup-status.sh setup.sh /tmp/resources/setup.log"
  if [[ $id == "W" ]]; then
    pvt_key=$TF_VAR_web_ssh_private_key
    cmd="bash ./web/check-setup-status.sh start-web.sh web/start-web.log"
  elif [[ $id == "I" ]]; then
    cmd="bash ./ipa/check-setup-status.sh setup-ipa.sh ipa/setup-ipa.log"
  fi
  > "${STATUS_FILE_PREFIX}.${id}"
  while true; do
    if [[ ! -f "${STATUS_FILE_PREFIX}.checking" ]]; then
      rm -f "${STATUS_FILE_PREFIX}.${id}"
      break
    fi
    local status=$(
      set +e;
      timeout 60 "ssh -q -o StrictHostKeyChecking=no -i '$pvt_key' centos@$ip '$cmd'" > "${STATUS_FILE_PREFIX}.${id}.tmp"
      if [[ $? == 0 ]]; then
        awk -v IP=$ip -v ID=$id -v KEY=$pvt_key '{print $1" "ID" "IP" "KEY}' "${STATUS_FILE_PREFIX}.${id}.tmp" > "${STATUS_FILE_PREFIX}.${id}"
        awk '{print $1}' "${STATUS_FILE_PREFIX}.${id}"
      fi
      rm -f "${STATUS_FILE_PREFIX}.${id}.tmp"
    )
    if [[ $status == "completed" || $status == "failed" ]]; then
      break
    fi
    sleep $((5 + (RANDOM % 5)))
  done
}

function start_checks() {
  touch "${STATUS_FILE_PREFIX}.checking"
  for ip in $(web_instance | web_attr public_ip); do
    > "${STATUS_FILE_PREFIX}.W.log"
    check_instance_status W $ip 2> "${STATUS_FILE_PREFIX}.W.log" &
    CPIDS="$CPIDS $!"
  done

  for ip in $(ipa_instance | ipa_attr public_ip); do
    > "${STATUS_FILE_PREFIX}.I.log"
    check_instance_status I $ip 2> "${STATUS_FILE_PREFIX}.I.log" &
    CPIDS="$CPIDS $!"
  done

  cluster_instances | awk '{print $1" "$4}' | while read index ip; do
    > "${STATUS_FILE_PREFIX}.${index}.log"
    check_instance_status $index $ip 2> "${STATUS_FILE_PREFIX}.${index}.log" &
    CPIDS="$CPIDS $!"
  done
}

function elapsed_time() {
  local start_epoch=$1
  python -c 'from datetime import datetime; print(datetime.now() - datetime.fromtimestamp('"$start_epoch"'))' | sed 's/\..*//'
}

function mod_time() {
  local path=$1
  python -c "import os; print(int(os.stat('$path').st_mtime))"
}

function print_header() {
  local line1="                     "
  local line2="Date/Time            "
  for ip in $(web_instance | web_attr public_ip); do
    line1="${line1} "
    line2="${line2}W"
  done

  for ip in $(ipa_instance | ipa_attr public_ip); do
    line1="${line1} "
    line2="${line2}I"
  done

  index=0
  for ip in $(cluster_instances | sort -k1n | cluster_attr public_ip); do
    if [[ $((index % 10)) == 0 && $index -ne 0 ]]; then
      line1="${line1}$((index / 10))"
    else
      line1="${line1} "
    fi
    line2="${line2}$((index % 10))"
    index=$((index+1))
  done

  echo "${C_WHITE}" >&2
  echo "Legend: ${C_WHITE}W${C_NORMAL} = Web server, ${C_WHITE}I${C_NORMAL} = IPA server, ${C_WHITE}[0-9]*${C_NORMAL} = Cluster instances" >&2
  echo "        ${C_NORMAL}${STATUS_FETCHING} = Fetching status, ${STATUS_RUNNING} = Running, ${STATUS_STALE} = Stale status" >&2
  echo "        ${STATUS_COMPLETED} = Completed, ${STATUS_FAILED} = Failed, ${STATUS_UNKNOWN} = Unknown" >&2
  echo "${C_WHITE}$line1" >&2
  echo "$line2  Elapsed Time" >&2
  echo -n "${C_NORMAL}" >&2
}

function get_instance_status() {
  local id=$1
  status_file="${STATUS_FILE_PREFIX}.${id}"
  mod_time=$(mod_time "$status_file")
  now=$(date +%s)
  local status="${STATUS_UNKNOWN}"
  if [[ -f $status_file ]]; then
    local result=$(awk '{print $1}' $status_file)
    if [[ $result == "" ]]; then
      status="${STATUS_FETCHING}"
    elif [[ $result == "completed" ]]; then
      status="${STATUS_COMPLETED}"
    elif [[ $result == "running" ]]; then
      if [[ $mod_time -lt $((now - 60)) ]]; then
        status="${STATUS_STALE}"
      else
        status="${STATUS_RUNNING}"
      fi
    elif [[ $result == "failed" ]]; then
      status="${STATUS_FAILED}"
    fi
  else
    status="${STATUS_FETCHING}"
  fi
  echo $status
}

function get_status() {
  local line="$(date +%Y-%m-%d\ %H:%M:%S)  "
  for ip in $(web_instance | web_attr public_ip); do
    line="${line}$(get_instance_status W)"
  done

  for ip in $(ipa_instance | ipa_attr public_ip); do
    line="${line}$(get_instance_status I)"
  done

  for index in $(cluster_instances | sort -k1n | cluster_attr index); do
    line="${line}$(get_instance_status $index)"
  done

  echo "$line  $(printf "%12s" $(elapsed_time $START_TIME))"
}

function total_instances() {
  echo $(($(cluster_instances | wc -l) + $(web_instance | wc -l) + $(ipa_instance | wc -l)))
}

function wait_for_completion() {
  local cnt=0
  local total=$(total_instances)
  while true; do
    if [[ $((cnt % 12)) -eq 0 ]]; then
      print_header
    fi
    local status_line=$(get_status)
    echo "$status_line" >&2

    # check for completion
    if [[ $(echo "$status_line " | egrep -o "[?X.]" | wc -l) -eq $total ]]; then
      if [[ $(echo "$status_line " | egrep -o "[.]" | wc -l) -eq $total ]]; then
        echo success
      else
        echo failed
      fi
      break
    fi

    sleep 5
    cnt=$((cnt+1))
  done
}

function fetch_logs() {
  echo "Fetching logs for failed instances"
  set -- $(ls -1 "${STATUS_FILE_PREFIX}".* | grep "${STATUS_FILE_PREFIX}\.[WI0-9][0-9]*$" | xargs awk '$1 != "completed" {print $2" "$3" "$4}')
  while [[ $# -gt 0 ]]; do
    id=$1; shift
    ip=$1; shift
    key=$1; shift
    local tmp_dir=/tmp/setup-${NAMESPACE}-${TIMESTAMP}-${id}-logs
    local tar_file=${tmp_dir}.tar.gz
    cmd="set -x; sudo rm -rf $tmp_dir && sudo mkdir -p $tmp_dir && (sudo cp /var/log/cloudera-scm-server/cloudera-scm-server.log /tmp/resources/setup.log ~centos/ipa/setup-ipa.log ~centos/web/start-web.log $tmp_dir 2>/dev/null || true) && sudo tar -zcf $tar_file $tmp_dir && sudo chmod 444 $tar_file"
    set +e
    timeout 60 "ssh -q -o StrictHostKeyChecking=no -i '$key' centos@$ip '$cmd'"
    if [[ $? != 0 ]]; then
      echo "WARNING: Failed to fetch logs from instance ${id}."
    else
      timeout 60 "scp -i '$key' centos@$ip:$tar_file $BASE_DIR/logs/"
      if [[ $? == 0 ]]; then
        echo "Logs of instance $id downloaded to ${C_WHITE}logs/$(basename $tar_file)${C_NORMAL}"
      else
        echo "WARNING: Failed to fetch logs from instance ${id}."
      fi
    fi
    set -e
  done
}

load_env $NAMESPACE
STATUS_DIR=${BASE_DIR}/.setup-status
mkdir -p "$STATUS_DIR"
find "$STATUS_DIR" -type f -mtime +2 -delete # delete old stuff, if any
TIMESTAMP=$(date +%s)
STATUS_FILE_PREFIX="$STATUS_DIR/setup-status.${NAMESPACE}.${TIMESTAMP}"

start_checks
status=$(wait_for_completion)
if [[ $status == "success" ]]; then
  echo "Instance deployment finished successfully"
else
  echo "${C_RED}WARNING: The deployment of at least one instance failed to complete.${C_NORMAL}"
  if [[ ${NO_LOG_FETCH:-} == "" ]]; then
    confirm=Y
    if [[ ${NO_PROMPT:-} == "" ]]; then
      echo -n "Do you want to fetch the logs for the failed instance(s)? (Y|n) "
      read confirm
    fi
    if [[ $(echo "$confirm" | tr 'a-z' 'A-Z') != "N" ]]; then
      fetch_logs
    fi
  fi
fi