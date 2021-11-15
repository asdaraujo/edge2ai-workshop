#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
NO_DOCKER=1
unset SSH_AUTH_SOCK SSH_AGENT_PID

source ${BASE_DIR}/common.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  abort
fi
NAMESPACE=$1

#SKIP_IF_MISSING_AWSCLI=1
load_env $NAMESPACE

exit 0