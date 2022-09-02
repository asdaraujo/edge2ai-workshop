#!/bin/bash
BASE_DIR=$(cd "$(dirname $0)"; pwd -L)

function suppress_deprecation_warning() {
  egrep -v "from cryptography.hazmat.backends|CryptographyDeprecationWarning"
}
source /opt/rh/rh-python38/enable

set -u
set -e

if [[ $# -lt 2 && $(expr "${1:-}" : '^[0-9]*$') -gt 0 ]]; then
  TARGET_WORKSHOP=base
  TARGET_LAB=$1
else
  TARGET_WORKSHOP=${1:-base}
  TARGET_LAB=${2:-99}
fi

export THE_PWD=$(cat $BASE_DIR/the_pwd.txt)
if [[ $THE_PWD == "" ]]; then
  echo "Please set and export the THE_PWD environment variable."
  exit 1
fi

if [[ -f /keytabs/admin.keytab ]]; then
  kinit -kt /keytabs/admin.keytab admin
fi

cd $BASE_DIR
python3 -c "import labs; labs.workshop_teardown(target_workshop='${TARGET_WORKSHOP}')" 2> >(suppress_deprecation_warning >&2)
python3 -c "import labs; labs.workshop_setup(target_workshop='${TARGET_WORKSHOP}', target_lab=${TARGET_LAB})" 2> >(suppress_deprecation_warning >&2)
echo "Done!"
