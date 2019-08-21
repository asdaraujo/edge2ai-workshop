#!/bin/bash
set -u
set -e
BASE_DIR=$(cd $(dirname $0); pwd -L)
CLUSTER_ID=$1
PROXY_PORT=8157

if [ ! -f .key.file.name -o ! -f .instance.list ]; then
  $BASE_DIR/list-details.sh > /dev/null
fi
PUBLIC_DNS=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $2}' .instance.list)
PUBLIC_IP=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $3}' .instance.list)
PRIVATE_DNS=$(awk '$1 ~ /-'$CLUSTER_ID'$/{print $4}' .instance.list)
KEY_FILE=$BASE_DIR/$(cat $BASE_DIR/.key.file.name)

ssh -o StrictHostKeyChecking=no -i $KEY_FILE -CND $PROXY_PORT centos@$PUBLIC_DNS &
CHILD_PID=$!

trap "kill $CHILD_PID" 0

rm -rf $HOME/chrome-for-demo
mkdir $HOME/chrome-for-demo
touch "$HOME/chrome-for-demo/First Run"

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir="$HOME/chrome-for-demo" \
  --proxy-server="socks5://localhost:8157" \
  --window-size=1184,854 \
  http://$PRIVATE_DNS:7180 \
  http://$PRIVATE_DNS:10080/efm/ui \
  http://$PRIVATE_DNS:8080/nifi/ \
  http://$PRIVATE_DNS:18080/nifi-registry \
  http://$PRIVATE_DNS:7788 \
  http://$PRIVATE_DNS:9991 \
  http://$PRIVATE_DNS:8888 \
  http://cdsw.$PUBLIC_IP.nip.io

