#!/bin/bash
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/common.sh

function syntax() {
  echo "Syntax: $0 <namespace>"
  show_namespaces
}

if [ $# -lt 1 ]; then
  syntax
  exit 1
fi
NAMESPACE=$1
load_env $NAMESPACE

echo -n "Fetching current deployment state... "
refresh_tf
echo "state refreshed"

echo "Opening public access to web server"
web_sg=$(security_groups web)
add_ingress "$web_sg" 0.0.0.0/0 tcp 80 "PUBLIC REGISTRATION" force

cat <<EOF
${C_YELLOW}
The Web Server is open for registration and accessible from the public Internet.
Please provide the following details to the workshop attendees:
  
  Web Server: ${C_BG_MAGENTA}${C_WHITE}http://$(web_instance | web_attr public_ip)${C_NORMAL}${C_YELLOW}
  Registration code: ${C_BG_MAGENTA}${C_WHITE}$(registration_code)${C_NORMAL}

Once they finish registering, press ENTER to close the public web access.
${C_NORMAL}
EOF

while true; do
  echo "${C_YELLOW}Press ENTER to close registration...${C_NORMAL}"
  set +e
  read -t 1 dummy
  ret=$?
  set -e
  if [[ $ret == 0 ]]; then
    break
  fi
  $BASE_DIR/sync-ip-addresses.sh "${NAMESPACE}" no_refresh 2>/dev/null
done

echo "Closing public access to the web server"
remove_ingress "$web_sg" 0.0.0.0/0 tcp 80 force

echo "Processing remaining access grants"
$BASE_DIR/sync-ip-addresses.sh "${NAMESPACE}" 2>/dev/null

