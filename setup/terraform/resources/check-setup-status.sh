#!/bin/bash
set -o errexit
set -o nounset

if [[ $# -ne 2 ]]; then
  echo "Syntax: $0 <setup_script_name> <log_path>"
  exit 1
fi

SCRIPT_NAME=$1
LOG_PATH=$2

LAST_STATUS=$(grep -o "STATUS:.*" $LOG_PATH | tail -1)

CNT=$(ps -ef | grep "$SCRIPT_NAME" | egrep -v "$0|grep" | wc -l)
if [[ $CNT -gt 0 ]]; then
  echo "running $LAST_STATUS"
else
  CNT=$(grep 'Setup return code: 0' $LOG_PATH 2> /dev/null | wc -l)
  if [[ $CNT -eq 0 ]]; then
    echo "failed $LAST_STATUS"
  else
    echo "completed $LAST_STATUS"
  fi
fi