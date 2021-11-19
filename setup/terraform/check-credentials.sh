#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source ${BASE_DIR}/common-basics.sh

if [ $# != 1 ]; then
  echo "Syntax: $0 <namespace>"
  show_namespaces
  abort
fi
NAMESPACE=$1

NO_DOCKER=1
source ${BASE_DIR}/common.sh

#SKIP_IF_MISSING_AWSCLI=1
load_env $NAMESPACE

exit 0