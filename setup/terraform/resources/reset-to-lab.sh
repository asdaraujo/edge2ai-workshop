#!/bin/bash
set -u
set -e
BASE_DIR=$(cd "$(dirname $0)"; pwd -L)

TARGET_LAB=${1:-99}
CA_CERT=/opt/cloudera/security/x509/truststore.pem
if [[ -f $CA_CERT ]]; then
  export NIFI_CA_CERT=$CA_CERT
  export REQUESTS_CA_BUNDLE=$CA_CERT
fi

cd $BASE_DIR
echo "Executing global teardown"
python3 -c "import utils; utils.global_teardown()"
echo "Running all setup functions less than Lab ${TARGET_LAB}"
python3 -c "import utils; utils.global_setup(target_lab=${TARGET_LAB})"
echo "Done"
