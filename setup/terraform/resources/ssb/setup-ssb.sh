#!/bin/bash

BASE_DIR=$(cd "$(dirname $0)"; pwd -L)

# Patch flink_api_handler.py for it to work with insecure clusters
sed -i.bak "s/\(^ *self._full_url = 'http\)s/\1/" /opt/cloudera/parcels/FLINK/lib/flink/python/console_venv/eventador-frontend/console/libs/flink_api_handler.py
# Patch yarn_handler.py for it to work with insecure clusters
sed -i.bak -E 's/^( *(if self.keytab_location|flink_cmd.extend.*-Dsecurity.kerberos.login.principal|"-Dsecurity.kerberos.login.keytab))/#\1/' /opt/cloudera/parcels/FLINK/lib/flink/python/console_venv/lib/python3.6/site-packages/eventador_core/yarn_handler.py
# Patch streambuilder_api.py to match the right parcel version
sed -i.bak 's/1.11.1-csa1.3.0.0/1.11-csa1.3.0.0/' /opt/cloudera/parcels/FLINK/lib/flink/python/console_venv/eventador-frontend/console/api/streambuilder_api.py

## Create missing streambuilder symlinks
#jar_file=$(ls -1 /opt/cloudera/parcels/FLINK/lib/flink/opt/cloudera/eventador/streambuilder-*.jar | tail -1)
#rm -f cj
#curl -L --cookie-jar cj --cookie cj "http://edge2ai-1.dim.local:8000/login" > /dev/null
#curl -L --cookie-jar cj --cookie cj "http://edge2ai-1.dim.local:8000/api/v1/sb-versions/f7435c9ef876452c9abf66da9f603bc8" | jq -r '.data[]' | while read version; do
#  target_file=/opt/cloudera/parcels/FLINK/lib/flink/opt/cloudera/eventador/streambuilder-${version}.jar
#  if [[ ! -h $target_file && ! -f $target_file ]]; then
#    echo "Creating link $target_file"
#    ln -s $jar_file $target_file
#  fi
#done
#rm -f cj

# Update Eventador kafka endpoint
export PYTHONHOME="/opt/cloudera/parcels/FLINK/lib/flink/python/console_venv"
export LD_LIBRARY_PATH="/opt/cloudera/parcels/FLINK/lib/flink/python/console_venv/lib64/"
export CONSOLE_PORT=8001
export CONSOLE_CONFIG_FILE=$(ls -d /run/cloudera-scm-agent/process/*-sql_stream_builder-STREAMING_SQL_CONSOLE/ssb-conf/ssb-console-conf.yaml | head -n1)
export CORE_SYSTEM_CONFIG_FILE=$(ls -d /run/cloudera-scm-agent/process/*-sql_stream_builder-STREAMING_SQL_CONSOLE/ssb-conf/ssb-console-conf.yaml | head -n1)
su -p ssb -c 'cd /opt/cloudera/parcels/FLINK/lib/flink/python/console_venv/eventador-frontend/console && ../../../console_venv/bin/python3 -W ignore '"${BASE_DIR}"'/python/update_hostmap.py'

# Restart SSB
curl -X POST -u admin:admin 'http://edge2ai-1.dim.local:7180/api/v40/clusters/OneNodeCluster/services/sql_stream_builder/commands/restart'
