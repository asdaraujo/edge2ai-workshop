#!/bin/bash
# Works on MacOS only
set -o errexit
set -o nounset
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/lib/common-basics.sh

if [ $# != 2 -a $# != 3 ]; then
  echo "Syntax: $0 <namespace> <cluster_number> [socks_proxy_port]"
  show_namespaces
  exit 1
fi
NAMESPACE=$1
CLUSTER_ID=$2
PROXY_PORT=${3:-}

export NO_DOCKER_EXEC=1
source $BASE_DIR/lib/common.sh

SERVICE_URLS=$(try_in_docker $NAMESPACE 'source $BASE_DIR/resources/common.sh; validate_stack $NAMESPACE $BASE_DIR/resources; get_service_urls')
if [ "$SERVICE_URLS" == "" ]; then
  echo "ERROR: Couldn't retrieve the service URLs for namespace $NAMESPACE."
  exit 1
fi

PUBLIC_DNS=$(try_in_docker $NAMESPACE "public_dns $CLUSTER_ID")
PUBLIC_IP=$(try_in_docker $NAMESPACE "public_ip $CLUSTER_ID")
if [ "$PROXY_PORT" != "" ]; then
  PROXY_PORT="--proxy-server=socks5://localhost:$PROXY_PORT"
fi

CM_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url CM) $PUBLIC_IP)
EFM_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url EFM) $PUBLIC_IP)
NIFI_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url NIFI) $PUBLIC_IP)
NIFIREG_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url NIFIREG) $PUBLIC_IP)
SR_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url SR) $PUBLIC_IP)
SMM_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url SMM) $PUBLIC_IP)
HUE_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url HUE) $PUBLIC_IP)
SSB_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url SSB) $PUBLIC_IP)
CDSW_URL=$(url_for_ip $(echo "$SERVICE_URLS" | service_url CDSW) $PUBLIC_IP)

#kerb_auth_for_cluster $CLUSTER_ID

BROWSER_DIR=$HOME/.chrome-for-demo.${NAMESPACE}.${CLUSTER_ID}
rm -rf ${BROWSER_DIR}
mkdir ${BROWSER_DIR}
touch "${BROWSER_DIR}/First Run"

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir="${BROWSER_DIR}" \
  --window-size=1184,854 \
  --auth-server-whitelist="$PUBLIC_DNS" \
  --auth-negotiate-delegatewhitelist="$PUBLIC_DNS" \
  $PROXY_PORT \
  $CM_URL \
  $EFM_URL \
  $NIFI_URL \
  $NIFIREG_URL \
  $SR_URL \
  $SMM_URL \
  $HUE_URL \
  $CDSW_URL \
  $SSB_URL

