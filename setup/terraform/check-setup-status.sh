#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [[ $# != 1 && $# != 2 ]]; then
  echo "Syntax: $0 <namespace> [start_epoch]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
START_TIME=${2:-$(date +%s)}

source $BASE_DIR/lib/common.sh

CURL=(curl -L -k --connect-timeout 5)
CPIDS=""

ICON_UNKNOWN="${C_BG_MAGENTA}${C_WHITE}?${C_NORMAL}"
ICON_CONNECTING="${C_WHITE}c${C_NORMAL}"
ICON_COMPLETED="${C_BG_GREEN}${C_BLACK}.${C_NORMAL}"
ICON_RUNNING="${C_BLUE}r${C_NORMAL}"
ICON_FAILED="${C_BG_RED}${C_BLACK}X${C_NORMAL}"
STATUS_UNKNOWN="unknown"
STATUS_CONNECTING="connecting"
STATUS_COMPLETED="completed"
STATUS_RUNNING="running"
STATUS_FAILED="failed"

function cleanup() {
  true
  if [[ ${STATUS_FILE_PREFIX:-} != "" ]]; then
    rm -f "${STATUS_FILE_PREFIX}".*
  fi
  if [[ ${CONTROL_PATH_PREFIX:-} != "" ]]; then
    for socket in "${CONTROL_PATH_PREFIX}".*; do
      ssh -O exit -S $socket dummy@host > /dev/null 2>&1
    done
  fi
}

function ensure_control_master() {
  local id=$1
  local ip=$2
  local pvt_key=$3
  local pid_file="${CONTROL_PATH_PREFIX}.${id}.parent_pid"
  set +e;
  ssh -q -O check -S "${CONTROL_PATH_PREFIX}.${id}" centos@$ip > /dev/null 2>&1
  local ret=$?
  set -e
  if [[ $ret == 0 ]]; then
    echo ready
    return
  fi

  check_pid=$(cat "$pid_file" 2>/dev/null || true)
  if [[ $check_pid != "" ]]; then
    if [[ $(ps -o pid | awk -v PID=$check_pid 'BEGIN {cnt = 0} $1 == PID {cnt += 1} END {print cnt}') -ne 0 ]]; then
      # connection still being established
      return
    fi
    rm -f "$pid_file"
  fi

  (
    timeout 60 "ssh -q -o StrictHostKeyChecking=no -f -N -M -o ControlPersist=2h -S '${CONTROL_PATH_PREFIX}.${id}' -i '$pvt_key' centos@$ip" &
    echo $! > "$pid_file"
    wait
    rm -f "$pid_file"
  ) >&2 &
}

function check_instance() {
  local id=$1
  local ip=$2
  local pvt_key=$TF_VAR_ssh_private_key
  local cmd="bash /tmp/resources/check-setup-status.sh setup.sh /tmp/resources/setup.log"
  if [[ $id == "W" ]]; then
    pvt_key=$TF_VAR_web_ssh_private_key
    cmd="bash ./web/check-setup-status.sh start-web.sh web/start-web.log"
  elif [[ ${id:0:1} == "E" ]]; then
    cmd="bash /tmp/resources/check-setup-status.sh 'setup-ecs.sh install-prereqs' /tmp/resources/setup-ecs.install-prereqs.log"
  elif [[ $id == "I" ]]; then
    cmd="bash ./ipa/check-setup-status.sh setup-ipa.sh ipa/setup-ipa.log"
  fi

  ready=$(ensure_control_master "$id" "$ip" "$pvt_key")
  if [[ $ready != "ready" ]]; then
    echo "$STATUS_CONNECTING $id $ip $pvt_key STATUS:Connecting"
    return
  fi

  ssh -q -S "${CONTROL_PATH_PREFIX}.${id}" centos@$ip "$cmd" > "${STATUS_FILE_PREFIX}.${id}.tmp"
  if [[ $? == 0 ]]; then
    awk -v IP="$ip" -v ID="$id" -v KEY="$pvt_key" -v UNKNOWN="$STATUS_UNKNOWN" '{status=$1; if (status == "") {status=UNKNOWN}; gsub(/.*STATUS:/, "STATUS:"); print status" "ID" "IP" "KEY" "$0}' "${STATUS_FILE_PREFIX}.${id}.tmp"
  fi
  rm -f "${STATUS_FILE_PREFIX}.${id}.tmp"
}

function instance_status() {
  awk '{print $1}'
}

function instance_short_status() {
  instance_status | while read status; do
    if [[ $status == "$STATUS_RUNNING" ]]; then
      status="${ICON_RUNNING}"
    elif [[ $status == "$STATUS_CONNECTING" ]]; then
      status="${ICON_CONNECTING}"
    elif [[ $status == "$STATUS_COMPLETED" ]]; then
      status="${ICON_COMPLETED}"
    elif [[ $status == "$STATUS_FAILED" ]]; then
      status="${ICON_FAILED}"
    else
      status="${ICON_UNKNOWN}"
    fi
    echo $status
  done
}

function instance_id() {
  awk '{print $2}'
}

function instance_ip() {
  awk '{print $3}'
}

function instance_key() {
  awk '{print $4}'
}

function instance_status_message() {
  awk '$1 != "'"$STATUS_COMPLETED"'" && $1 != "'"$STATUS_FAILED"'" && /STATUS:/{gsub(/.*STATUS:/, "["$2"] "); print}'
}

function elapsed_time() {
  local start_epoch=$1
  python -c 'from datetime import datetime; print(datetime.now() - datetime.fromtimestamp('"$start_epoch"'))' | sed 's/\..*//'
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

  ecs_count=$(ecs_instances | wc -l)
  index=0
  for ip in $(cluster_instances | sort -k1n | cluster_attr public_ip); do
    if [[ $((index % 10)) == 0 && $index -ne 0 ]]; then
      line1="${line1}$((index / 10))"
    else
      line1="${line1} "
    fi
    line2="${line2}$((index % 10))"
    if [[ $ecs_count -gt 0 ]]; then
      line1="${line1} "
      line2="${line2}E"
    fi
    index=$((index+1))
  done

  echo "${C_WHITE}" >&2
  echo "Legend: ${C_WHITE}W${C_NORMAL} = Web server, ${C_WHITE}I${C_NORMAL} = IPA server, ${C_WHITE}E${C_NORMAL} = ECS server, ${C_WHITE}[0-9]*${C_NORMAL} = Cluster instances" >&2
  echo "        ${C_NORMAL}${ICON_CONNECTING} = Connecting, ${ICON_RUNNING} = Running, ${ICON_COMPLETED} = Completed, ${ICON_FAILED} = Failed, ${ICON_UNKNOWN} = Unknown" >&2
  echo "${C_WHITE}$line1" >&2
  echo "$line2  Elapsed Time  Status" >&2
  echo -n "${C_NORMAL}" >&2
}

function get_status() {
  local line="$(date +%Y-%m-%d\ %H:%M:%S)  "
  local status_msg=""
  rm -f "$LATEST_STATUS_FILE"
  for ip in $(web_instance | web_attr public_ip); do
    result=$(check_instance W $ip | tee -a "$LATEST_STATUS_FILE")
    line="${line}$(echo "$result" | instance_short_status)"
    [[ $status_msg == "" ]] && status_msg=$(echo "$result" | instance_status_message)
  done

  for ip in $(ipa_instance | ipa_attr public_ip); do
    result=$(check_instance I $ip | tee -a "$LATEST_STATUS_FILE")
    line="${line}$(echo "$result" | instance_short_status)"
    [[ $status_msg == "" ]] && status_msg=$(echo "$result" | instance_status_message)
  done

  local -a ips
  local max_index=0
  while read index ip; do
    ips[$index]=$ip
    max_index=$index
  done <<< "$(cluster_instances | sort -k1n | cluster_attr index public_ip)"
  ecs_count=$(ecs_instances | wc -l)
  for index in $(seq 0 $max_index); do
    # CDP check
    ip=${ips[$index]}
    result=$(check_instance $index $ip | tee -a "$LATEST_STATUS_FILE")
    line="${line}$(echo "$result" | instance_short_status)"
    [[ $status_msg == "" ]] && status_msg=$(echo "$result" | instance_status_message)
    # ECS check
    if [[ $index -lt $ecs_count ]]; then
      ip=$(ecs_instances $index | ecs_attr public_ip)
      result=$(check_instance E$index $ip | tee -a "$LATEST_STATUS_FILE")
      line="${line}$(echo "$result" | instance_short_status)"
      [[ $status_msg == "" ]] && status_msg=$(echo "$result" | instance_status_message)
    fi
  done

  printf "%s  %12s  %s\n" "$line" "$(elapsed_time $START_TIME)" "$status_msg"
}

function total_instances() {
  echo $(($(cluster_instances | wc -l) + $(ecs_instances | wc -l) + $(web_instance | wc -l) + $(ipa_instance | wc -l)))
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
    if [[ $(egrep -c "^(${STATUS_COMPLETED}|${STATUS_FAILED}|${STATUS_UNKNOWN})" "$LATEST_STATUS_FILE") -eq $total ]]; then
      cp "$LATEST_STATUS_FILE" "${LATEST_STATUS_FILE}.final.$(date +%Y%m%d%H%M%S)"
      if [[ $(egrep -c "^${STATUS_COMPLETED}" "$LATEST_STATUS_FILE") -eq $total ]]; then
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
  echo "Fetching logs for failed instances. Please wait."
  set -- $(awk '$1 != "'"$STATUS_COMPLETED"'" {print $2" "$3" "$4}' "$LATEST_STATUS_FILE")
  while [[ $# -gt 0 ]]; do
    id=$1; shift
    ip=$1; shift
    key=$1; shift
    local tmp_dir=/tmp/setup-${NAMESPACE}-${TIMESTAMP}-${id}-logs
    local tar_file=${tmp_dir}.tar.gz
    cmd="sudo rm -rf $tmp_dir && sudo mkdir -p $tmp_dir && (sudo cp /var/log/cloudera-scm-server/cloudera-scm-server.log /tmp/resources/setup.log ~centos/ipa/setup-ipa.log ~centos/web/start-web.log $tmp_dir 2>/dev/null || true) && sudo tar -zcf $tar_file $tmp_dir 2>/dev/null && sudo chmod 444 $tar_file"
    set +e
    timeout 60 "ssh -q -o StrictHostKeyChecking=no -i '$key' centos@$ip '$cmd'"
    if [[ $? != 0 ]]; then
      echo "WARNING: Failed to fetch logs from instance ${id}."
    else
      mkdir -p $BASE_DIR/logs/
      local base_name=$(basename $tar_file)
      local target_file="${BASE_DIR}/logs/${base_name}"
      rm -f "$target_file"
      timeout 60 "scp -i '$key' centos@$ip:$tar_file '$target_file'"
      if [[ $? == 0 ]]; then
        echo "${C_WHITE}Logs of instance [$id] downloaded to: logs/${base_name}${C_NORMAL}"
      else
        echo "WARNING: Failed to fetch logs from instance ${id}."
      fi
    fi
    set -e
  done
}

STATUS_DIR=${BASE_DIR}/.setup-status
LATEST_STATUS_FILE=${STATUS_DIR}/latest-status.${NAMESPACE}
mkdir -p "$STATUS_DIR"
find "$STATUS_DIR" -type f -mtime +2 -delete 2> /dev/null # delete old stuff, if any
TIMESTAMP=$(date +%s)
CONTROL_PATH_PREFIX="/tmp/control-path.${NAMESPACE}.${TIMESTAMP}"
STATUS_FILE_PREFIX="$STATUS_DIR/setup-status.${NAMESPACE}.${TIMESTAMP}"

status=$(wait_for_completion)
if [[ $status == "success" ]]; then
  echo "Instance deployment finished successfully"
else
  echo "${C_RED}WARNING: The deployment of the following instance(s) failed to complete:${C_NORMAL}"
  echo -n "${C_YELLOW}"
  awk '$1 != "completed" {inst=$2; ip=$3; gsub(/.*STATUS:/, ""); printf "Instance: [%s], IP: %s, Latest status: %s\n", inst, ip, $0}' "$LATEST_STATUS_FILE"
  echo -n "${C_NORMAL}"
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
  exit 1
fi