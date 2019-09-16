#!/bin/bash
# Works on MacOS only

set -u
set -e

if [ $# != 1 ]; then
  echo "Syntax: $0 [cluster_number]"
  exit 1
fi

BASE_DIR=$(cd $(dirname $0); pwd -L)
CLUSTER_ID=$1
PROXY_PORT=8157

if [ ! -f .key.file.name -o ! -f .instance.list ]; then
  $BASE_DIR/list-details.sh > /dev/null
fi
PUBLIC_DNS=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $2}' .instance.list)
PUBLIC_IP=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $3}' .instance.list)
KEY_FILE=$BASE_DIR/$(cat $BASE_DIR/.key.file.name)

rm -rf $HOME/chrome-for-demo
mkdir $HOME/chrome-for-demo
touch "$HOME/chrome-for-demo/First Run"

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir="$HOME/chrome-for-demo" \
  --window-size=1184,854 \
  http://$PUBLIC_DNS:7180 \
  http://$PUBLIC_DNS:10080/efm/ui \
  http://$PUBLIC_DNS:8080/nifi/ \
  http://$PUBLIC_DNS:18080/nifi-registry \
  http://$PUBLIC_DNS:7788 \
  http://$PUBLIC_DNS:9991 \
  http://$PUBLIC_DNS:8888 \
  http://cdsw.$PUBLIC_IP.nip.io

