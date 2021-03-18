#!/bin/bash
set -u
set -e

BASE_DIR=$(cd $(dirname $0); pwd -P)

DATALOADER_DIR=/opt/dataloader
LOG_DIR=$DATALOADER_DIR/logs
DEP_FILE=$BASE_DIR/deployment.json
FLOW_TEMPLATE=$DATALOADER_DIR/IOT-Trucking-Fleet-Data-Flow-For-SMM.xml
LIB_DIR=$DATALOADER_DIR/lib

# Producer settings
ROUTES_LOCATION=$DATALOADER_DIR/routes/midwest
SECURE_MODE=NONSECURE
NUM_OF_EUROPE_TRUCKS=3
NUM_OF_CRITICAL_EVENT_PRODUCERS=5
# Consumer settings
SECURITY_PROTOCOL=PLAINTEXT

export BROKERS=
export ZK_ADDR=
export SR_ADDR=
export SR_URL=

CM_USER=admin
CM_PWD=supersecret1
CM_HOST=$(grep "^ *server_host" /etc/cloudera-scm-agent/config.ini | sed 's/ //g;s/.*=//')

declare -a KAFKA_TOPICS=(
  "gateway-west-raw-sensors" "gateway-central-raw-sensors" "gateway-east-raw-sensor"
  "gateway-europe-raw-sensors" "syndicate-geo-event-avro" "syndicate-speed-event-avro"
  "syndicate-geo-event-json" "syndicate-speed-event-json" "alerts-speeding-drivers"
  "syndicate-oil" "syndicate-battery" "syndicate-transmission" "syndicate-all-geo-critical-events"
  "fleet-supply-chain" "route-planning" "load-optimization" "fuel-logistics"
  "supply-chain" "predictive-alerts" "energy-mgmt" "audit-events" "compliance"
  "adjudication" "approval"
)
TOPIC_PARTITIONS=5

function install_packages() {
  # Install needed packages
  curl -k -L "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" > /usr/bin/jq
  chmod 555 /usr/bin/jq
}

function fetch_cm_config_and_set_vars() {
  API_VERSION=$(curl -k -L -u $CM_USER:$CM_PWD "http://$CM_HOST:7180/api/version" 2>/dev/null)
  curl -k -L -u $CM_USER:$CM_PWD "http://$CM_HOST:7180/api/$API_VERSION/cm/deployment" > $DEP_FILE 2>/dev/null
  echo -n "$(jq -r '.clusters[].services[].roles[] | select(.type == "SERVER").hostRef.hostname' $DEP_FILE):2181" > $BASE_DIR/.zk_addr
  echo -n "$(jq -r '.clusters[].services[].roles[] | select(.type == "SCHEMA_REGISTRY_SERVER").hostRef.hostname' $DEP_FILE):7788" > $BASE_DIR/.sr_addr
}

function get_zk_addr() {
  if [ ! -s $BASE_DIR/.zk_addr ]; then
    fetch_cm_config_and_set_vars
  fi
  cat $BASE_DIR/.zk_addr
}

function get_sr_addr() {
  if [ ! -s $BASE_DIR/.sr_addr ]; then
    fetch_cm_config_and_set_vars
  fi
  cat $BASE_DIR/.sr_addr
}

function get_sr_url() {
  echo "http://$(get_sr_addr)/api/v1"
}

function create_dirs_download_content() {
  # Create dirs
  mkdir -p $DATALOADER_DIR $LOG_DIR
  chmod 755 $DATALOADER_DIR/
  chown root:root $DATALOADER_DIR/
  rm -rf $DATALOADER_DIR/lib
  tar -C $DATALOADER_DIR/ -zxvf <(curl -k -L "https://edge2ai-workshop.s3-us-west-2.amazonaws.com/whoville/streaming-jars.tar.gz")
  tar -C $DATALOADER_DIR/ -zxvf <(curl -k -L "https://s3.us-west-2.amazonaws.com/edge2ai-workshop/whoville/routes.tar.gz")
}

function set_log_rotation() {
  # Set Logrotation
  if [ -f /etc/cron.daily/logrotate ]; then
    mv /etc/cron.daily/logrotate /etc/cron.hourly/
  fi
  cat > /etc/logrotate.d/dataloader << EOF
$LOG_DIR/*.log
$LOG_DIR/smm-ref-app
{
    rotate 2
    compress
    size 10M
    dateext
    dateformat -%s
    sharedscripts
    postrotate
        STATUS=\$(/opt/dataloader/smm-generator.sh status)
        if [ "\$STATUS" != "" ]; then
          /opt/dataloader/smm-generator.sh stop || true
          /opt/dataloader/smm-generator.sh start || true
          /opt/dataloader/smm-generator.sh status || true
        fi
    endscript
}
EOF
}

function create_kafka_topics() {
  # Create Kafka topics
  echo "Creating Kafka Topics"
  for topic in "${KAFKA_TOPICS[@]}"; do
     kafka-topics \
      --create \
      --if-not-exists \
      --zookeeper "$(get_zk_addr)/kafka" \
      --replication-factor 1 \
      --partitions $TOPIC_PARTITIONS \
      --topic "$topic"
  done
}

function get_brokers() {
  if [ ! -s $BASE_DIR/.brokers ]; then
    for broker_id in $(zookeeper-client -server $(get_zk_addr) ls /kafka/brokers/ids | grep "^\[" | sed 's/[][]//g'); do
      zookeeper-client -server $(hostname -f) get /kafka/brokers/ids/$broker_id | tail -1 | jq -r '"\(.host):\(.port)"'
    done | tr "\n" "," | sed 's/,$//' > $BASE_DIR/.brokers
  fi
  cat $BASE_DIR/.brokers
}

function register_schemas() {
  echo "Starting Loading Schemas into Registry"
  java \
    -Xms256m -Xmx2g \
    -cp "$LIB_DIR/*" \
    cloudera.cdf.csp.schema.refapp.trucking.schemaregistry.TruckSchemaRegistryLoader \
    $(get_sr_url)
  echo "Finished Loading Schemas into Registry"
}

function create_truck() {
  local app_class=$1
  local client_producer_id=$2
  local topic=$3
  local wait_time=$4
  local log_file=$5
  local driver_id=${6:-}
  local route_name=${7:-}
  local route_id=${8:-}
  if [ "$app_class" == "truck_fleet" ]; then
    app_class=cloudera.cdf.refapp.trucking.simulator.runner.smm.SMMSimulationRunnerTruckFleetApp
  elif [ "$app_class" == "single_driver" ]; then
    app_class=cloudera.cdf.refapp.trucking.simulator.runner.smm.SMMSimulationRunnerSingleDriverApp
  fi
  echo "  Producer ID: $client_producer_id, type: ${app_class##*.}"
  (
    cd $LOG_DIR
    nohup java \
      -Xms256m -Xmx2g \
      -cp "$LIB_DIR/*" \
      "$app_class" \
      -1 \
      cloudera.cdf.refapp.trucking.simulator.domain.transport.Truck \
      cloudera.cdf.refapp.trucking.simulator.producer.smm.SMMTruckEventCSVGenerator \
      1 \
      "$ROUTES_LOCATION" \
      "$wait_time" \
      "$(get_brokers)" \
      ALL_STREAMS \
      "$SECURE_MODE" \
      "$client_producer_id" \
      "$topic" \
      "$driver_id" \
      "$route_name" \
      "$route_id" &>> $log_file &
  )
  sleep 1
}

function create_europe_trucks() {
  echo "----------------- Starting International Fleet ----------------- "
  for ((i=1;i<=NUM_OF_EUROPE_TRUCKS;i++)); do
    local clientProducerId='minifi-eu-i'$i
    local logFile=$LOG_DIR/eu${i}.log
    local waitTime=$((i*2000))
    create_truck truck_fleet $clientProducerId gateway-europe-raw-sensors $waitTime $logFile
  done
}

function create_all_geo_critical_event_producers() {
  echo "----------------- Starting Geo Event Critical Producers  ----------------- "
  for ((i=1;i<=NUM_OF_CRITICAL_EVENT_PRODUCERS;i++)); do
    local clientProducerId='geo-critical-event-collector-i'$i
    local logFile=$LOG_DIR/geo-critical-event${i}.log
    local waitTime=$((i*1000))
    create_truck truck_fleet $clientProducerId syndicate-all-geo-critical-events $waitTime $logFile
  done
}

function create_micro_service_producers() {
  echo "----------------- Starting Micro Service Producers  ----------------- "
  local topics=(route-planning load-optimization fuel-logistics supply-chain predictive-alerts energy-mgmt audit-events compliance adjudication approval syndicate-oil syndicate-battery syndicate-transmission)
  local apps=(route load-optimizer fuel supply-chain predictive energy audit compliance adjudication approval micro-service-oil micro-service-batter micro-service-transmissiony)
  i=0
  for topic in "${topics[@]}"; do
    topicName=$topic
    clientProducerId=${apps[i]}-apps
    logFile=$LOG_DIR/$clientProducerId.log
    waitTime=$((i*2150))
    create_truck truck_fleet $clientProducerId $topicName $waitTime $logFile
    i=$((i+1))
  done
}

function create_us_fleet() {
  echo "----------------- Starting US West Truck Fleet ----------------- "
  create_truck single_driver minifi-truck-w1 gateway-west-raw-sensors 5000 $LOG_DIR/w1.log 10 "Saint Louis to Tulsa" 10
  create_truck single_driver minifi-truck-w2 gateway-west-raw-sensors 6000 $LOG_DIR/w2.log 13 "Des Moines to Chicago" 13
  create_truck single_driver minifi-truck-w3 gateway-west-raw-sensors 7000 $LOG_DIR/w3.log 14 "Joplin to Kansas City" 14
  echo "----------------- Starting US Central Truck Fleet ----------------- "
  create_truck single_driver minifi-truck-c1 gateway-central-raw-sensors 8000 $LOG_DIR/c1.log 11 "Saint Louis to Chicago" 11
  create_truck single_driver minifi-truck-c2 gateway-central-raw-sensors 9000 $LOG_DIR/c2.log 15 "Memphis to Little Rock" 15
  create_truck single_driver minifi-truck-c3 gateway-central-raw-sensors 10000 $LOG_DIR/c3.log 16 "Peoria to Ceder Rapids" 16
  echo "----------------- Starting US East Truck Fleet ----------------- "
  create_truck single_driver minifi-truck-e1 gateway-east-raw-sensors 11000 $LOG_DIR/e1.log 12 "Saint Louis to Memphis" 12
  create_truck single_driver minifi-truck-e2 gateway-east-raw-sensors 12000 $LOG_DIR/e2.log 17 "Springfield to KC Via Columbia" 17
  create_truck single_driver minifi-truck-e3 gateway-east-raw-sensors 13000 $LOG_DIR/e3.log 18 "Des Moines to Chicago Route 2" 18
}

function deploy_producers() {
  echo "Running Producer Deployment Functions"
  create_us_fleet
  create_europe_trucks
  create_micro_service_producers
  create_all_geo_critical_event_producers
  echo "Finished Producer Deployment Functions"
}

function stop_all_producers() {
  local pids=$(ps -ef | grep SMMSimulation | grep -v grep | awk '{print $2}')
  if [ "$pids" != "" ]; then
    kill -9 $pids
  fi
}

function create_string_consumer() {
  local topics=$1
  local group_id=$2
  local client_id=$3
  local log_file=$4
  echo "  Consumer Group ID: $group_id, type: LoggerStringEventConsumer"
  (
    cd $LOG_DIR
    nohup java \
      -Xms256m -Xmx2g \
      -cp "$LIB_DIR/*" \
      cloudera.cdf.csp.smm.refapp.consumer.impl.LoggerStringEventConsumer \
      --bootstrap.servers $(get_brokers) \
      --schema.registry.url $(get_sr_addr) \
      --security.protocol $SECURITY_PROTOCOL \
      --topics "$topics" \
      --groupId "$group_id" \
      --clientId "$client_id" \
      --auto.offset.reset latest &>> "$log_file" &
  )
  sleep 1
}

function create_avro_consumer() {
  local topics=$1
  local group_id=$2
  local client_id=$3
  local log_file=$4
  echo "  Consumer Group ID: $group_id, type: LoggerAvroEventConsumer"
  (
    cd $LOG_DIR
    nohup java \
      -Xms256m -Xmx2g \
      -cp "$LIB_DIR/*" \
      cloudera.cdf.csp.smm.refapp.consumer.impl.LoggerAvroEventConsumer \
      --bootstrap.servers $(get_brokers) \
      --schema.registry.url $(get_sr_addr) \
      --security.protocol $SECURITY_PROTOCOL \
      --topics "$topics" \
      --groupId "$group_id" \
      --clientId "$client_id" \
      --auto.offset.reset latest &>> "$log_file" &
  )
  sleep 1
}

function create_kafka_streams_consumer_for_truck_geo_avro() {
  local topicName="syndicate-geo-event-avro"
  local groupId="kafka-streams-analytics-geo-event"
  local clientId="consumer-1"
  local logFile="$LOG_DIR/kafka-streams-analytics-geo-event.log"
  create_avro_consumer $topicName $groupId $clientId $logFile
}

function create_spark_streaming_consumer_for_truck_geo_avro() {
  local topicName="syndicate-geo-event-avro"
  local groupId="spark-streaming-analytics-geo-event"
  local clientId="consumer-1"
  local logFile="$LOG_DIR/spark-streaming-analytics-geo-event.log"
  create_avro_consumer $topicName $groupId $clientId $logFile
}

function create_flink_streaming_consumer_for_truck_geo_avro() {
  local topicName="syndicate-geo-event-avro"
  local groupId="flink-analytics-geo-event"
  local clientId="consumer-1"
  local logFile="$LOG_DIR/flink-analytics-geo-event.log"
  create_avro_consumer $topicName $groupId $clientId $logFile
}

function create_micro_service_consumers() {
  local topics=(route-planning load-optimization fuel-logistics supply-chain predictive-alerts energy-mgmt audit-events compliance adjudication approval)
  local services=(route load-optimizer fuel supply-chain predictive energy audit compliance adjudication approval)
  local i=0
  for topic in "${topics[@]}"; do
    local topicName=$topic
    local groupId=${services[i]}-micro-service
    local clientId=consumer-1
    local logFile=$LOG_DIR/$groupId-$clientId.log
    create_string_consumer $topicName $groupId $clientId $logFile
    i=$((i+1))
  done
}

function deploy_consumers() {
  echo "Running Consumer Deployment Functions"
  echo "----------------- Starting Avro Consumers  ----------------- "
  create_kafka_streams_consumer_for_truck_geo_avro
  create_spark_streaming_consumer_for_truck_geo_avro
  create_flink_streaming_consumer_for_truck_geo_avro
  echo "----------------- Starting Micro Service Consumers  ----------------- "
  create_micro_service_consumers
  echo "Finished Consumer Deployment Functions"
}

function stop_all_consumers() {
  local pids=$(ps -ef | grep cloudera.cdf.csp.smm.refapp.consumer.impl.Logger | grep -v grep | awk '{print $2}')
  if [ "$pids" != "" ]; then
    kill -9 $pids
  fi
}

function process_status() {
  ps -ef | grep -v grep | egrep -o "LoggerAvroEventConsumer|LoggerStringEventConsumer|SMMSimulationRunnerTruckFleetApp|SMMSimulationRunnerSingleDriverApp" | sort | uniq -c
}

function import_nifi_flow() {
  local flow_xml=$DATALOADER_DIR/customized-flow.xml
  local import_script=$DATALOADER_DIR/import-flow.py

  # replace template placeholders
  sed "s/HOSTNAME/$(hostname -f)/g" $FLOW_TEMPLATE > $flow_xml

  # create import script
  cat > $import_script <<'EOF'
#!/usr/bin/python3
# Script configured for NO TLS
# Script will run on a random node once on destination cluster.
import logging
import time
import socket
import sys
import nipyapi

flow_xml = sys.argv[1]

logger = logging.getLogger('post_create_cluster.py')
fhandler = logging.FileHandler(filename='/root/post_create_cluster.log', mode='a')
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
fhandler.setFormatter(formatter)
logger.addHandler(fhandler)
logger.setLevel(logging.INFO)

# Connect to NiFi etc
hostname = socket.gethostname()
logger.info("Connecting to NiFi on " + hostname)
nipyapi.utils.set_endpoint('http://' + hostname + ':8080/nifi-api')

# Add Template to NiFi
while True:
    try:
        root_pg_id = nipyapi.canvas.get_root_pg_id()
        logger.info("Deploying NiFi Template")
        template = nipyapi.templates.upload_template(pg_id=root_pg_id,template_file=flow_xml)
        r = nipyapi.templates.deploy_template(root_pg_id, template.id)
        pg_id = r.flow.process_groups[0].id
        break
    except nipyapi.nifi.rest.ApiException as e:
        if e.status != 409: # Cluster is still in the process of voting on the appropriate Data Flow.
            logger.error("NiFi connection failed with status %s" % (e.status,))
            raise
        logger.info("NiFi not ready yet")
        time.sleep(15)

# get parents PG
pg_flow = nipyapi.canvas.get_process_group('IOT Trucking Fleet - Data Flow')
print("Parent Flow ID is: " + pg_flow.id)

# start controller services
pass_cnt = 1
while True:
    is_done = True
    print("=== Pass %d ========" % (pass_cnt,))
    cont_services = nipyapi.nifi.FlowApi().get_controller_services_from_group(pg_flow.id)
    for cse in cont_services.controller_services:
        cs = 'CS: %s (id: %s, status: %s, validation: %s)' % (cse.component.name, cse.id, cse.status.run_status, cse.status.validation_status)
        if cse.status.run_status == 'ENABLED':
            print('STARTED  ' + cs)
            continue
        is_done = False
        if cse.status.run_status == 'DISABLED' and cse.status.validation_status == 'VALID':
            print('Starting ' + cs)
            nipyapi.canvas.schedule_controller(cse, True, True)
        else:
            print('WAIT     ' + cs)
    if is_done:
        break
    pass_cnt += 1
    time.sleep(10)

logger.info("Done!")
# Done
EOF

  set +u
  source /opt/rh/rh-python36/enable
  set -u
  pip install requests nipyapi
  python $import_script $flow_xml
}

## MAIN ##
ACTION=${1:-}
if [ "$ACTION" == "setup" ]; then
  install_packages
  create_dirs_download_content
  set_log_rotation
  create_kafka_topics
  register_schemas
  import_nifi_flow
elif [ "$ACTION" == "start" ]; then
  deploy_producers
  deploy_consumers
elif [ "$ACTION" == "stop" ]; then
  stop_all_producers
  stop_all_consumers
elif [ "$ACTION" == "status" ]; then
  process_status
else
  echo "Syntax: $0 <setup|stop|start>"
  exit 1
fi
