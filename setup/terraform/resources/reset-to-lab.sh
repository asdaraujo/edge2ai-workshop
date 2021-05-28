#!/bin/bash
BASE_DIR=$(cd "$(dirname $0)"; pwd -L)

source /opt/rh/rh-python36/enable

set -u
set -e

TARGET_LAB=${1:-99}

export THE_PWD=$(cat $BASE_DIR/the_pwd.txt)
if [[ $THE_PWD == "" ]]; then
  echo "Please set and export the THE_PWD environment variable."
  exit 1
fi

cd $BASE_DIR
echo "Executing global teardown"
python3 -c "import utils; utils.global_teardown()"
echo "Running all setup functions less than Lab ${TARGET_LAB}"
python3 -c "import utils; utils.global_setup(target_lab=${TARGET_LAB})"
echo "Done"
