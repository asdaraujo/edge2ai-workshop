#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Common utilities for Python scripts
"""

import logging
import re
import requests
import time
import os
import sys
from inspect import getmembers
from contextlib import contextmanager
from impala.dbapi import connect
from nipyapi import config, canvas, versioning, nifi
from nipyapi.nifi.rest import ApiException


LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)

CONSUMER_GROUP_ID = 'iot-sensor-consumer'
PRODUCER_CLIENT_ID = 'nifi-sensor-data'

_EFM_API_URL = 'http://edge2ai-1.dim.local:10080/efm/api'
_NIFI_URL = 'http://edge2ai-1.dim.local:8080/nifi'
_NIFI_API_URL = 'http://edge2ai-1.dim.local:8080/nifi-api'
_NIFIREG_URL = 'http://edge2ai-1.dim.local:18080'
_NIFIREG_API_URL = 'http://edge2ai-1.dim.local:18080/nifi-registry-api'
_SCHREG_API_URL = 'http://edge2ai-1.dim.local:7788/api/v1'
_SMM_API_URL = 'http://edge2ai-1.dim.local:8585'

_SCHEMA_URI = 'https://raw.githubusercontent.com/asdaraujo/edge2ai-workshop/master/sensor.avsc'

_CDSW_MODEL_NAME = 'IoT Prediction Model'
_CDSW_USERNAME = 'admin'
_CDSW_PASSWORD = 'supersecret1'
_CDSW_FULL_NAME = 'Workshop Admin'
_CDSW_EMAIL = 'admin@cloudera.com'

PG_NAME = 'Process Sensor Data'

_AGENT_MANIFESTS = None

_CREATE_KUDU_TABLE = """
CREATE TABLE IF NOT EXISTS sensors
(
 sensor_id INT,
 sensor_ts TIMESTAMP,
 sensor_0 DOUBLE,
 sensor_1 DOUBLE,
 sensor_2 DOUBLE,
 sensor_3 DOUBLE,
 sensor_4 DOUBLE,
 sensor_5 DOUBLE,
 sensor_6 DOUBLE,
 sensor_7 DOUBLE,
 sensor_8 DOUBLE,
 sensor_9 DOUBLE,
 sensor_10 DOUBLE,
 sensor_11 DOUBLE,
 is_healthy INT,
 PRIMARY KEY (sensor_ID, sensor_ts)
)
PARTITION BY HASH PARTITIONS 16
STORED AS KUDU
TBLPROPERTIES ('kudu.num_tablet_replicas' = '1');
"""

_DROP_KUDU_TABLE = "DROP TABLE IF EXISTS sensors;"

# General helper functions


def get_public_ip():
    retries = 3
    while retries > 0:
        resp = requests.get('http://ifconfig.me')
        if resp.status_code == requests.codes.ok:
            return resp.text
        retries -= 1
        time.sleep(1)
    raise RuntimeError('Failed to get the public IP address.')


def api_request(method, url, expected_code=requests.codes.ok, **kwargs):
    resp = requests.request(method, url, **kwargs)
    if resp.status_code != expected_code:
        raise RuntimeError('Request to URL %s returned code %s (expected was %s), Response: %s' % (resp.url, resp.status_code, expected_code, resp.text))
    return resp


@contextmanager
def exception_context(obj):
    try:
        yield
    except:
        print('Exception context: %s' % (obj,))
        raise


def retry_test(max_retries=0, wait_time_secs=0):
    def wrap(f):
        def wrapped_f(*args, **kwargs):
            retries = 0
            while True:
                try:
                    f(*args, **kwargs)
                    break
                except Exception:
                    if retries >= max_retries:
                        raise
                    else:
                        retries += 1
                        time.sleep(wait_time_secs)
                        print('Retry #%d' % (retries,))
        return wrapped_f
    return wrap

# CDSW helper functions


def get_cdsw_api():
    return 'http://cdsw.%s.nip.io/api/v1' % (get_public_ip(),)


def get_cdsw_altus_api():
    return 'http://cdsw.%s.nip.io/api/altus-ds-1' % (get_public_ip(),)


def get_cdsw_model_access_key():
    def _open_cdsw_session():
        s = requests.Session()
        r = s.post(get_cdsw_api() + '/authenticate', json={'login': _CDSW_USERNAME, 'password': _CDSW_PASSWORD})
        s.headers.update({'Authorization': 'Bearer ' + r.json()['auth_token']})
        return s

    def _get_cdsw_model(s):
        r = s.post(get_cdsw_altus_api() + '/models/list-models', json={'projectOwnerName': 'admin', 'latestModelDeployment': True, 'latestModelBuild': True})
        models = [m for m in r.json() if m['name'] == 'IoT Prediction Model']
        model = None
        for m in models:
            if m['name'] == _CDSW_MODEL_NAME:
                model = m
        if not model:
            raise RuntimeError('Model %s not found.' % (_CDSW_MODEL_NAME,))
        return model

    s = _open_cdsw_session()
    while True:
        model = _get_cdsw_model(s)
        if model['latestModelDeployment']['status'] == 'deployed':
            return model['accessKey']
        LOG.debug('Model not deployed yet. Waiting for deployment to finish.')
        time.sleep(10)

# Kudu helper functions


def create_kudu_table():
    conn = connect(host='localhost', port=21050)
    cursor = conn.cursor()
    cursor.execute(_CREATE_KUDU_TABLE)
    result = cursor.fetchall()
    if not any(x in str(result) for x in ["Table has been created", "Table already exists"]):
        raise RuntimeError('Failed to create Kudu table, response was:', str(result))


def drop_kudu_table():
    conn = connect(host='localhost', port=21050)
    cursor = conn.cursor()
    cursor.execute(_DROP_KUDU_TABLE)
    result = cursor.fetchall()
    if not any(x in str(result) for x in ["Table has been dropped", "Table does not exist"]):
        raise RuntimeError('Failed to drop Kudu table, response was:', str(result))

# NiFi helper functions


def create_processor(pg, name, processor_type, position, config):
    proc_type = canvas.get_processor_type(processor_type, identifier_type='name')
    return canvas.create_processor(pg, proc_type, position, name, config)


def create_funnel(pg_id, position):
    funnel = canvas.create_funnel(pg_id, position=position)
    # the below update is needed due to a nipyapi bug
    nifi.FunnelApi().update_funnel(funnel.id, {
        "revision": funnel.revision,
        "component": {
            "id": funnel.id,
            "position": {
                "x": position[0],
                "y": position[1]
            }
        }
    })
    return funnel


def update_connection(source, destination, new_destination):
    conn = [c for c in canvas.list_all_connections() if c.source_id == source.id and c.destination_id == destination.id][0]
    return nifi.ConnectionsApi().update_connection(conn.id, {
        "revision": conn.revision,
        "component": {
            "id": conn.id,
            "destination": {
                "id": new_destination.id,
                "groupId": new_destination.component.parent_group_id,
                "type": "INPUT_PORT"
            }
        }
    })


def get_controller_type(controller_type):
    types = [ctype for ctype in canvas.list_all_controller_types() if ctype.type == controller_type]
    if types:
        return types[0]
    return None


def create_controller(pg, controller_type, properties, start, name=None):
    controller_type = get_controller_type(controller_type)
    controller = canvas.create_controller(pg, controller_type, name)
    controller = canvas.get_controller(controller.id, 'id')
    canvas.update_controller(controller, nifi.ControllerServiceDTO(properties=properties))
    controller = canvas.get_controller(controller.id, 'id')
    canvas.schedule_controller(controller, start)
    return canvas.get_controller(controller.id, 'id')


def nifi_delete_all(pg):
    canvas.schedule_process_group(pg.id, False)
    for conn in canvas.list_all_connections(pg.id):
        LOG.debug('Connection: ' + conn.id)
        canvas.delete_connection(conn, purge=True)
    for input_port in canvas.list_all_input_ports(pg.id):
        LOG.debug('Input Port: ' + input_port.id)
        canvas.delete_port(input_port)
    for output_port in canvas.list_all_output_ports(pg.id):
        LOG.debug('Output Port: ' + output_port.id)
        canvas.delete_port(output_port)
    for funnel in canvas.list_all_funnels(pg.id):
        LOG.debug('Funnel: ' + funnel.id)
        canvas.delete_funnel(funnel)
    for processor in canvas.list_all_processors(pg.id):
        LOG.debug('Processor: ' + processor.id)
        canvas.delete_processor(processor, force=True)
    for process_group in canvas.list_all_process_groups(pg.id):
        if pg.id == process_group.id:
            continue
        LOG.debug('Process Group: ' + process_group.id)
        nifi_delete_all(process_group)
        canvas.delete_process_group(process_group, force=True)

# EFM helper functions


def efm_api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _EFM_API_URL + endpoint
    return api_request(method, url, expected_code, **kwargs)


def efm_api_get(endpoint, expected_code=requests.codes.ok, **kwargs):
    return efm_api_request('GET', endpoint, expected_code, **kwargs)


def efm_api_post(endpoint, expected_code=requests.codes.ok, **kwargs):
    return efm_api_request('POST', endpoint, expected_code, **kwargs)


def efm_api_delete(endpoint, expected_code=requests.codes.ok, **kwargs):
    return efm_api_request('DELETE', endpoint, expected_code, **kwargs)


def efm_get_client_id():
    resp = efm_api_get('/designer/client-id')
    return resp.text


def efm_get_agent_manifests():
    global _AGENT_MANIFESTS
    if not _AGENT_MANIFESTS:
        resp = efm_api_get('/agent-manifests')
        _AGENT_MANIFESTS = resp.json()
    return _AGENT_MANIFESTS


def efm_get_flow(agent_class):
    resp = efm_api_get('/designer/flows')
    json = resp.json()
    assert('elements' in json)
    assert(len(json['elements']) == 1)
    flow = json['elements'][0]
    return (flow['identifier'], flow['rootProcessGroupIdentifier'])


def efm_get_processor_bundle(processor_type):
    for manifest in efm_get_agent_manifests():
        for bundle in manifest['bundles']:
            for processor in bundle['componentManifest']['processors']:
                if processor['type'] == processor_type:
                    return {
                               'group': processor['group'],
                               'artifact': processor['artifact'],
                               'version': processor['version'],
                           }
    raise RuntimeError('Processor type %s not found in agent manifest.' % (processor_type,))


def efm_create_processor(flow_id, pg_id, name, processor_type, position, properties, auto_terminate=None):
    endpoint = '/designer/flows/{flowId}/process-groups/{pgId}/processors'.format(flowId=flow_id, pgId=pg_id)
    body = {
      'revision': {
        'clientId': efm_get_client_id(),
        'version': 0
      },
      'componentConfiguration': {
        'name': name,
        'type': processor_type,
        'bundle': efm_get_processor_bundle(processor_type),
        'position': {
          'x': position[0],
          'y': position[1]
        },
        'properties': properties,
        'autoTerminatedRelationships': auto_terminate,
      }
    }
    resp = efm_api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()['componentConfiguration']['identifier']


def efm_create_remote_processor_group(flow_id, pg_id, name, rpg_url, transport_protocol, position):
    endpoint = '/designer/flows/{flowId}/process-groups/{pgId}/remote-process-groups'.format(flowId=flow_id, pgId=pg_id)
    body = {
      'revision': {
        'clientId': efm_get_client_id(),
        'version': 0
      },
      'componentConfiguration': {
        'name': name,
        'position': {
          'x': position[0],
          'y': position[1]
        },
        'transportProtocol': transport_protocol,
        'targetUri': rpg_url,
        'targetUris': rpg_url,
      }
    }
    resp = efm_api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()['componentConfiguration']['identifier']


def efm_get_all_by_type(flow_id, obj_type):
    endpoint = '/designer/flows/{flowId}'.format(flowId=flow_id)
    resp = efm_api_get(endpoint, headers={'Content-Type': 'application/json'})
    obj_type_alt = re.sub(r'[A-Z]', lambda x: '-' + x.group(0).lower(), obj_type)
    for obj in resp.json()['flowContent'][obj_type]:
        endpoint = '/designer/flows/{flowId}/{objType}/{objId}'.format(flowId=flow_id, objType=obj_type_alt, objId=obj['identifier'])
        resp = efm_api_get(endpoint, headers={'Content-Type': 'application/json'})
        yield resp.json()


def efm_delete_by_type(flow_id, obj, obj_type):
    obj_id = obj['componentConfiguration']['identifier']
    version = obj['revision']['version']
    client_id = obj['revision']['clientId']
    obj_type_alt = re.sub(r'[A-Z]', lambda x: '-' + x.group(0).lower(), obj_type)
    endpoint = '/designer/flows/{flowId}/{objType}/{objId}?version={version}&clientId={clientId}'.format(flowId=flow_id, objType=obj_type_alt, objId=obj_id, version=version, clientId=client_id)
    resp = efm_api_delete(endpoint, headers={'Content-Type': 'application/json'})
    LOG.debug('Object of type %s (%s) deleted.', obj_type, obj_id)


def efm_delete_all(flow_id):
    for obj_type in ['connections', 'remoteProcessGroups', 'processors', 'inputPorts', 'outputPorts']:
        for conn in efm_get_all_by_type(flow_id, obj_type):
            efm_delete_by_type(flow_id, conn, obj_type)


def efm_create_connection(flow_id, pg_id, source_id, source_type, destination_id, destination_type, relationships, source_port=None, destination_port=None):
    def _get_endpoint(endpoint_id, endpoint_type, endpoint_port):
        if endpoint_type == 'PROCESSOR':
            return {'id': endpoint_id, 'type': 'PROCESSOR'}
        elif endpoint_type == 'REMOTE_INPUT_PORT':
            return {'groupId': endpoint_id, 'type': 'REMOTE_INPUT_PORT', 'id': endpoint_port}
        else:
            raise RuntimeError('Endpoint type %s is not supported' % (endpoint_type,))

    endpoint = '/designer/flows/{flowId}/process-groups/{pgId}/connections'.format(flowId=flow_id, pgId=pg_id)
    body = {
      'revision': {
        'clientId': efm_get_client_id(),
        'version': 0
      },
      'componentConfiguration': {
        'source': _get_endpoint(source_id, source_type, source_port),
        'destination': _get_endpoint(destination_id, destination_type, destination_port),
        'selectedRelationships': relationships,
      }
    }
    resp = efm_api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()


def efm_publish_flow(flow_id, comments):
    endpoint = '/designer/flows/{flowId}/publish'.format(flowId=flow_id)
    body = {
      'comments': comments,
    }
    resp = efm_api_post(endpoint, headers={'Content-Type': 'application/json'}, json=body)

# NiFi Registry helper functions


def save_flow_ver(process_group, registry_client, bucket, flow_name=None,
                  flow_id=None, comment='', desc='', refresh=True, force=False):
    """
    TODO: Only needed here due to a nipyapi bug. Can be removed in the next nipyapi version
    """
    import nipyapi
    if refresh:
        target_pg = nipyapi.canvas.get_process_group(process_group.id, 'id')
    else:
        target_pg = process_group
    if nipyapi.utils.check_version('1.10.0') <= 0:
        body = nipyapi.nifi.StartVersionControlRequestEntity(
            process_group_revision=target_pg.revision,
            versioned_flow=nipyapi.nifi.VersionedFlowDTO(
                bucket_id=bucket.identifier,
                comments=comment,
                description=desc,
                flow_name=flow_name,
                flow_id=flow_id,
                registry_id=registry_client.id,
                action='FORCE_COMMIT' if force else 'COMMIT'
            )
        )
    else:
        # Prior versions of NiFi do not have the 'action' property and will fail
        body = nipyapi.nifi.StartVersionControlRequestEntity(
            process_group_revision=target_pg.revision,
            versioned_flow={
                'bucketId': bucket.identifier,
                'comments': comment,
                'description': desc,
                'flowName': flow_name,
                'flowId': flow_id,
                'registryId': registry_client.id
            }
        )
    with nipyapi.utils.rest_exceptions():
        return nipyapi.nifi.VersionsApi().save_to_flow_registry(
            id=target_pg.id,
            body=body
        )


def nifireg_api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _NIFIREG_API_URL + endpoint
    return api_request(method, url, expected_code, **kwargs)


def nifireg_api_delete(endpoint, expected_code=requests.codes.ok, **kwargs):
    return nifireg_api_request('DELETE', endpoint, expected_code, **kwargs)


def nifireg_delete_flows(identifier, identifier_type='name'):
    bucket = versioning.get_registry_bucket(identifier, identifier_type)
    if bucket:
        for flow in versioning.list_flows_in_bucket(bucket.identifier):
            endpoint = '/buckets/{bucketId}/flows/{flowId}'.format(bucketId=flow.bucket_identifier, flowId=flow.identifier)
            resp = nifireg_api_delete(endpoint, headers={'Content-Type': 'application/json'})

# Schema Registry helper functions


def schreg_api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _SCHREG_API_URL + endpoint
    return api_request(method, url, expected_code, **kwargs)


def schreg_api_get(endpoint, expected_code=requests.codes.ok, **kwargs):
    return schreg_api_request('GET', endpoint, expected_code, **kwargs)


def schreg_api_post(endpoint, expected_code=requests.codes.ok, **kwargs):
    return schreg_api_request('POST', endpoint, expected_code, **kwargs)


def schreg_api_delete(endpoint, expected_code=requests.codes.ok, **kwargs):
    return schreg_api_request('DELETE', endpoint, expected_code, **kwargs)


def schreg_get_versions(name):
    endpoint = '/schemaregistry/schemas/{name}/versions'.format(name=name)
    resp = schreg_api_get(endpoint, headers={'Content-Type': 'application/json'})
    return resp.json()['entities']


def schreg_get_all_schemas():
    endpoint = '/schemaregistry/schemas'
    resp = schreg_api_get(endpoint, headers={'Content-Type': 'application/json'})
    return resp.json()['entities']


def schreg_delete_all_schemas():
    for schema in schreg_get_all_schemas():
        schreg_delete_schema(schema['schemaMetadata']['name'])


def schreg_delete_schema(name):
    endpoint = '/schemaregistry/schemas/{name}'.format(name=name)
    resp = schreg_api_delete(endpoint, headers={'Content-Type': 'application/json'})
    LOG.debug('Schema %s deleted.', name)


def schreg_create_schema(name, description, schema_text):
    assert schema_text is not None
    assert len(schema_text) > 0
    endpoint = '/schemaregistry/schemas'
    body = {
        'type': 'avro',
        'schemaGroup': 'Kafka',
        'name': name,
        'description': description,
        'compatibility': 'BACKWARD',
        'validationLevel': 'ALL',
        'evolve': True
    }
    resp = schreg_api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    schreg_create_schema_version(name, schema_text)


def schreg_create_schema_version(name, schema_text):
    endpoint = '/schemaregistry/schemas/{name}/versions'.format(name=name)
    body = {
        'schemaText': schema_text
    }
    resp = schreg_api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)


def read_in_schema(uri=_SCHEMA_URI):
    if 'SCHEMA_FILE' in os.environ and os.path.exists(os.environ['SCHEMA_FILE']):
        return open(os.environ['SCHEMA_FILE']).read()
    else:
        r = requests.get(_SCHEMA_URI)
        if r.status_code == 200:
            return r.text
        raise ValueError("Unable to retrieve schema from URI, response was %s", r.response_code)

# SMM helper functions


def smm_api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _SMM_API_URL + endpoint
    return api_request(method, url, expected_code, **kwargs)


def smm_api_get(endpoint, expected_code=requests.codes.ok, **kwargs):
    return smm_api_request('GET', endpoint, expected_code, **kwargs)

# MAIN


def set_environment(run_id):
    if not run_id:
        run_id = str(int(time.time()))

    # Initialize NiFi API
    config.nifi_config.host = _NIFI_API_URL
    config.registry_config.host = _NIFIREG_API_URL

    # Get NiFi root PG
    root_pg = canvas.get_process_group(canvas.get_root_pg_id(), 'id')

    # Get EFM flow
    flow_id, efm_pg_id = efm_get_flow('iot-1')

    return (run_id, root_pg, efm_pg_id, flow_id)


def global_teardown(run_id=None):
    (run_id, root_pg, efm_pg_id, flow_id) = set_environment(run_id)

    canvas.schedule_process_group(root_pg.id, False)
    while True:
        failed = False
        for controller in canvas.list_all_controllers(root_pg.id):
            try:
                canvas.schedule_controller(controller, False)
                LOG.debug('Controller %s stopped.', controller.component.name)
            except ApiException as exc:
                if exc.status == 409 and 'is referenced by' in exc.body:
                    LOG.debug('Controller %s failed to stop. Will retry later.', controller.component.name)
                    failed = True
        if not failed:
            break

    nifi_delete_all(root_pg)
    efm_delete_all(flow_id)
    schreg_delete_all_schemas()
    reg_client = versioning.get_registry_client('NiFi Registry')
    if reg_client:
        versioning.delete_registry_client(reg_client)
    nifireg_delete_flows('SensorFlows')
    drop_kudu_table()


def global_setup(run_id=None, schema_text=None, cdsw_flag=True, target_lab=99):
    class _Env(object): pass
    env = _Env()
    env.run_id, env.root_pg, env.efm_pg_id, env.flow_id = set_environment(run_id)
    env.schema_text = schema_text if schema_text is not None else read_in_schema()
    LOG.info("Using Schema: %s", schema_text)
    env.cdsw_flag = cdsw_flag

    lab_setup_functions = [o for o, p in getmembers(sys.modules[__name__]) if 'lab' in o]
    LOG.info("Found Lab Setup Functions: %s", str(lab_setup_functions))
    for lab_setup_func in lab_setup_functions:
        if int(lab_setup_func[3]) < target_lab:
            LOG.info("[{0}] is numbered lower than target [lab{1}], executing".format(lab_setup_func, target_lab))
            globals()[lab_setup_func](env)
        else:
            LOG.info("[{0}] is numbered higher than target [lab{1}], skipping".format(lab_setup_func, target_lab))

def wait_for_data(timeout_secs=120):
    LOG.info("Setup complete, waiting for data to flow in NiFi")
    while timeout_secs:
        bytes_in = canvas.get_process_group(PG_NAME, 'name').status.aggregate_snapshot.bytes_in
        if bytes_in > 0:
            break
        timeout_secs -= 1
        LOG.info("Data not Flowing yet, sleeping for 3")
        time.sleep(3)

    # wait a few more seconds just to let the pipes to be primed
    time.sleep(10)


def lab1_sensor_simulator(env):
    LOG.info("Running step1_sensor_simulator")
    # Create a processor to run the sensor simulator
    gen_data = create_processor(env.root_pg, 'Generate Test Data', 'org.apache.nifi.processors.standard.ExecuteProcess', (0, 0),
        {
            'properties': {
                'Command': 'python3',
                'Command Arguments': '/opt/demo/simulate.py',
            },
            'schedulingPeriod': '1 sec',
            'schedulingStrategy': 'TIMER_DRIVEN',
            'autoTerminatedRelationships': ['success'],
        }
    )
    canvas.schedule_processor(gen_data, True)


def lab2_edge_flow(env):
    LOG.info("Running step2_edge_flow")
    # Create input port and funnel in NiFi
    env.from_gw = canvas.create_port(env.root_pg.id, 'INPUT_PORT', 'from Gateway', 'STOPPED', (0, 200))
    funnel_position = (96, 350)
    env.temp_funnel = create_funnel(env.root_pg.id, (96, 350))
    canvas.create_connection(env.from_gw, env.temp_funnel)

    # Create flow in EFM
    env.consume_mqtt = efm_create_processor(
        env.flow_id, env.efm_pg_id,
        'ConsumeMQTT',
        'org.apache.nifi.processors.mqtt.ConsumeMQTT',
        (100, 100),
        {
            'Broker URI': 'tcp://edge2ai-1.dim.local:1883',
            'Client ID': 'minifi-iot',
            'Topic Filter': 'iot/#',
            'Max Queue Size': '60',
        })
    env.nifi_rpg = efm_create_remote_processor_group(env.flow_id, env.efm_pg_id, 'Remote PG', _NIFI_URL, 'HTTP', (100, 400))
    env.consume_conn = efm_create_connection(env.flow_id, env.efm_pg_id, env.consume_mqtt, 'PROCESSOR', env.nifi_rpg, 'REMOTE_INPUT_PORT', ['Message'], destination_port=env.from_gw.id)

    # Create a bucket in NiFi Registry to save the edge flow versions
    if not versioning.get_registry_bucket('IoT'):
        versioning.create_registry_bucket('IoT')

    # Publish/version the flow
    efm_publish_flow(env.flow_id, 'First version - ' + str(env.run_id))


def lab3_register_schema(env):
    LOG.info("Running step3_register_schema")
    # Create Schema
    schreg_create_schema('SensorReading', 'Schema for the data generated by the IoT sensors', env.schema_text)


def lab4_nifi_flow(env):
    LOG.info("Running step4_nifi_flow")
    # Create a bucket in NiFi Registry to save the edge flow versions
    env.sensor_bucket = versioning.get_registry_bucket('SensorFlows')
    if not env.sensor_bucket:
        env.sensor_bucket = versioning.create_registry_bucket('SensorFlows')

    # Create NiFi Process Group
    env.reg_client = versioning.create_registry_client('NiFi Registry', _NIFIREG_URL, 'The registry...')
    env.sensor_pg = canvas.create_process_group(env.root_pg, PG_NAME, (330, 350))
    #env.sensor_flow = versioning.save_flow_ver(env.sensor_pg, env.reg_client, env.sensor_bucket, flow_name='SensorProcessGroup', comment='Enabled version control - ' + env.run_id)
    env.sensor_flow = save_flow_ver(env.sensor_pg, env.reg_client, env.sensor_bucket, flow_name='SensorProcessGroup', comment='Enabled version control - ' + str(env.run_id))

    # Create controller services
    env.sr_svc = create_controller(env.sensor_pg, 'org.apache.nifi.schemaregistry.hortonworks.HortonworksSchemaRegistry', {'url': _SCHREG_API_URL}, True)
    env.json_reader_svc = create_controller(env.sensor_pg, 'org.apache.nifi.json.JsonTreeReader', {'schema-access-strategy': 'schema-name', 'schema-registry': env.sr_svc.id}, True)
    env.json_writer_svc = create_controller(env.sensor_pg, 'org.apache.nifi.json.JsonRecordSetWriter', {'schema-access-strategy': 'schema-name', 'schema-registry': env.sr_svc.id, 'Schema Write Strategy': 'hwx-schema-ref-attributes'}, True)

    # Create flow
    sensor_port = canvas.create_port(env.sensor_pg.id, 'INPUT_PORT', 'Sensor Data', 'RUNNING', (0, 0))

    upd_attr = create_processor(env.sensor_pg, 'Set Schema Name', 'org.apache.nifi.processors.attributes.UpdateAttribute', (0, 100),
        {
            'properties': {
                'schema.name': 'SensorReading',
            },
        }
    )
    canvas.create_connection(sensor_port, upd_attr)

    pub_kafka = create_processor(env.sensor_pg, 'Publish to Kafka topic: iot', 'org.apache.nifi.processors.kafka.pubsub.PublishKafkaRecord_2_0', (0, 300),
        {
            'properties': {
                'bootstrap.servers': 'edge2ai-1.dim.local:9092',
                'topic': 'iot',
                'record-reader': env.json_reader_svc.id,
                'record-writer': env.json_writer_svc.id,
                'use-transactions': 'false',
                'attribute-name-regex': 'schema.*',
                'client.id': PRODUCER_CLIENT_ID,
            },
            'autoTerminatedRelationships': ['success'],
        }
    )
    canvas.create_connection(upd_attr, pub_kafka, ['success'])

    fail_funnel = create_funnel(env.sensor_pg.id, (600, 343))
    canvas.create_connection(pub_kafka, fail_funnel, ['failure'])

    # Commit changes
    #versioning.save_flow_ver(env.sensor_pg, env.reg_client, env.sensor_bucket, flow_id=env.sensor_flow.version_control_information.flow_id, comment='First version - ' + env.run_id)
    save_flow_ver(env.sensor_pg, env.reg_client, env.sensor_bucket, flow_id=env.sensor_flow.version_control_information.flow_id, comment='First version - ' + str(env.run_id))

    # Start flow
    canvas.schedule_process_group(env.root_pg.id, True)

    # Update "from Gateway" input port to connect to the process group
    update_connection(env.from_gw, env.temp_funnel, sensor_port)


def lab6_expand_edge_flow(env):
    LOG.info("Running step6_expand_edge_flow")
    # Expand the CEM flow
    extract_proc = efm_create_processor(
        env.flow_id, env.efm_pg_id,
        'Extract sensor_0 and sensor1 values',
        'org.apache.nifi.processors.standard.EvaluateJsonPath',
        (500, 100),
        {
            'Destination': 'flowfile-attribute',
            'sensor_0': '$.sensor_0',
            'sensor_1': '$.sensor_1',
        },
        auto_terminate=['failure', 'unmatched', 'sensor_0', 'sensor_1'])
    filter_proc = efm_create_processor(
        env.flow_id, env.efm_pg_id,
        'Filter Errors',
        'org.apache.nifi.processors.standard.RouteOnAttribute',
        (500, 400),
        {
            'Routing Strategy': 'Route to Property name',
            'error': '${sensor_0:ge(500):or(${sensor_1:ge(500)})}',
        },
        auto_terminate=['error'])
    efm_delete_by_type(env.flow_id, env.consume_conn, 'connections')
    env.consume_conn = efm_create_connection(env.flow_id, env.efm_pg_id, env.consume_mqtt, 'PROCESSOR', extract_proc, 'PROCESSOR', ['Message'])
    extract_conn = efm_create_connection(env.flow_id, env.efm_pg_id, extract_proc, 'PROCESSOR', filter_proc, 'PROCESSOR', ['matched'])
    filter_conn = efm_create_connection(env.flow_id, env.efm_pg_id, filter_proc, 'PROCESSOR', env.nifi_rpg, 'REMOTE_INPUT_PORT', ['unmatched'], destination_port=env.from_gw.id)

    # Publish/version flow
    efm_publish_flow(env.flow_id, 'Second version - ' + str(env.run_id))


def lab7_rest_and_kudu(env):
    LOG.info("Running step7_rest_and_kudu")
    # Create controllers
    json_reader_with_schema_svc = create_controller(env.sensor_pg,
                                                    'org.apache.nifi.json.JsonTreeReader',
                                                    {'schema-access-strategy': 'hwx-schema-ref-attributes', 'schema-registry': env.sr_svc.id},
                                                    True,
                                                    name='JsonTreeReader - With schema identifier')
    rest_lookup_svc = create_controller(env.sensor_pg,
                                        'org.apache.nifi.lookup.RestLookupService',
                                        {'rest-lookup-url': get_cdsw_altus_api() + '/models/call-model', 'rest-lookup-record-reader': env.json_reader_svc.id, 'rest-lookup-record-path': '/response'},
                                        True)

    # Build flow
    fail_funnel = create_funnel(env.sensor_pg.id, (1400, 340))

    consume_kafka = create_processor(env.sensor_pg, 'Consume Kafka iot messages', 'org.apache.nifi.processors.kafka.pubsub.ConsumeKafkaRecord_2_0', (700, 0),
        {
            'properties': {
                'bootstrap.servers': 'edge2ai-1.dim.local:9092',
                'topic': 'iot',
                'topic_type': 'names',
                'record-reader': json_reader_with_schema_svc.id,
                'record-writer': env.json_writer_svc.id,
                'honor-transactions': 'false',
                'group.id': CONSUMER_GROUP_ID,
                'auto.offset.reset': 'latest',
                'header-name-regex': 'schema.*',
            },
        }
    )
    canvas.create_connection(consume_kafka, fail_funnel, ['parse.failure'])

    predict = create_processor(env.sensor_pg, 'Predict machine health', 'org.apache.nifi.processors.standard.LookupRecord', (700, 200),
        {
            'properties': {
                'record-reader': json_reader_with_schema_svc.id,
                'record-writer': env.json_writer_svc.id,
                'lookup-service': rest_lookup_svc.id,
                'result-record-path': '/response',
                'routing-strategy': 'route-to-success',
                'result-contents': 'insert-entire-record',
                'mime.type': "toString('application/json', 'UTF-8')",
                'request.body': "concat('{\"accessKey\":\"', '${cdsw.access.key}', '\",\"request\":{\"feature\":\"', /sensor_0, ', ', /sensor_1, ', ', /sensor_2, ', ', /sensor_3, ', ', /sensor_4, ', ', /sensor_5, ', ', /sensor_6, ', ', /sensor_7, ', ', /sensor_8, ', ', /sensor_9, ', ', /sensor_10, ', ', /sensor_11, '\"}}')",
                'request.method': "toString('post', 'UTF-8')",
            },
        }
    )
    canvas.create_connection(predict, fail_funnel, ['failure'])
    canvas.create_connection(consume_kafka, predict, ['success'])

    update_health = create_processor(env.sensor_pg, 'Update health flag', 'org.apache.nifi.processors.standard.UpdateRecord', (700, 400),
        {
            'properties': {
                'record-reader': json_reader_with_schema_svc.id,
                'record-writer': env.json_writer_svc.id,
                'replacement-value-strategy': 'record-path-value',
                '/is_healthy': '/response/result',
            },
        }
    )
    canvas.create_connection(update_health, fail_funnel, ['failure'])
    canvas.create_connection(predict, update_health, ['success'])

    write_kudu = create_processor(env.sensor_pg, 'Write to Kudu', 'org.apache.nifi.processors.kudu.PutKudu', (700, 600),
        {
            'properties': {
                'Kudu Masters': 'edge2ai-1.dim.local:7051',
                'Table Name': 'impala::default.sensors',
                'record-reader': json_reader_with_schema_svc.id,
            },
        }
    )
    canvas.create_connection(write_kudu, fail_funnel, ['failure'])
    canvas.create_connection(update_health, write_kudu, ['success'])

    monitor_activity = create_processor(env.sensor_pg, 'Monitor Activity', 'org.apache.nifi.processors.standard.MonitorActivity', (700, 800),
        {
            'properties': {
                'Threshold Duration': '45 secs',
                'Continually Send Messages': 'true',
            },
            'autoTerminatedRelationships': ['activity.restored', 'success'],
        }
    )
    canvas.create_connection(monitor_activity, fail_funnel, ['inactive'])
    canvas.create_connection(write_kudu, monitor_activity, ['success'])

    # Version flow
    save_flow_ver(env.sensor_pg, env.reg_client, env.sensor_bucket, flow_id=env.sensor_flow.version_control_information.flow_id, comment='Second version - ' + str(env.run_id))

    # Prepare Impala/Kudu table
    create_kudu_table()

    # Set the variable with the CDSW access key
    if env.cdsw_flag:
        canvas.update_variable_registry(env.sensor_pg, [('cdsw.access.key', get_cdsw_model_access_key())])

    # Start everything
    canvas.schedule_process_group(env.root_pg.id, True)
