#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nipyapi import nifi, canvas, config, security, parameters, utils
from . import *
from . import nifireg, cm


DEFAULT_SSL_SERVICE_NAME = 'Default NiFi SSL Context Service'
DEFAULT_TRUSTSTORE_LOCATION = '/opt/cloudera/security/jks/truststore.jks'
DEFAULT_TRUSTSTORE_PASSWORD = get_the_pwd()
DEFAULT_KEYSTORE_LOCATION = '/opt/cloudera/security/jks/keystore.jks'
DEFAULT_KEYSTORE_PASSWORD = get_the_pwd()

DEFAULT_KEYTAB_SERVICE_NAME = 'KeytabControllerService'
DEFAULT_KEYTAB_LOCATION = '/keytabs/admin.keytab'
DEFAULT_KEYTAB_PRINCIPAL = 'admin'

DEFAULT_SCHREG_SERVICE_NAME = 'Schema Registry'
DEFAULT_JSON_READER_SERVICE_NAME = 'JsonTreeReader'
DEFAULT_JSON_WRITER_SERVICE_NAME = 'JsonRecordSetWriter'
DEFAULT_AVRO_WRITER_SERVICE_NAME = 'AvroRecordSetWriter'
DEFAULT_REST_LOOKUP_SERVICE_NAME = 'RestLookupService'
DEFAULT_HTTP_CTX_MAP_SERVICE_NAME = 'StandardHttpContextMap'

_NIFI_VERSION = None


def _get_port():
    return '8443' if is_tls_enabled() else '8080'


def get_url():
    return '%s://%s:%s/nifi' % (get_url_scheme(), get_hostname(), _get_port())


def _get_api_url():
    return '%s://%s:%s/nifi-api' % (get_url_scheme(), get_hostname(), _get_port())


def get_cfm_version():
    global _NIFI_VERSION
    if not _NIFI_VERSION:
        _NIFI_VERSION = cm.get_product_version('CFM')
    return [int(x) for x in re.sub('[^0-9.].*', '', _NIFI_VERSION).split('.')]


def create_processor(pg, name, processor_types, position, cfg):
    if isinstance(processor_types, str):
        processor_types = [processor_types]
    all_proc_types = canvas.list_all_processor_types().processor_types
    for processor_type in processor_types:
        choosen_type = [p for p in all_proc_types if p.type == processor_type]
        if choosen_type:
            return canvas.create_processor(pg, choosen_type[0], position, name, cfg)
    raise RuntimeError("Processor types {} not found in available list: {}",
                       processor_types, [p.type for p in all_proc_types])


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


def create_connection(source, target, relationships=None, name=None, bends=None, label_index=None, z_index=None):
    conn = canvas.create_connection(source, target, relationships, name)
    if bends:
        update_connection(conn=conn, bends=bends, label_index=label_index, z_index=z_index)
    return conn


def update_connection(source=None, target=None, new_target=None, bends=None, label_index=None, z_index=None, conn=None):
    assert (source is not None and target is not None and conn is None) or \
           (source is None and target is None and conn is not None)
    if not conn:
        conn = [c for c in canvas.list_all_connections()
                if c.source_id == source.id and c.destination_id == target.id][0]
    component = {
        "id": conn.id,
    }
    if new_target:
        component['destination'] = {
            "id": new_target.id,
            "groupId": new_target.component.parent_group_id,
            "type": "INPUT_PORT"
        }
    if bends:
        component['bends'] = bends
    if label_index is not None:
        component['labelIndex'] = label_index
    if z_index is not None:
        component['zIndex'] = z_index
    return nifi.ConnectionsApi().update_connection(conn.id, {
        "revision": conn.revision,
        "component": component,
    })


def get_controller(service_name, identifier_type='name'):
    objs = canvas.list_all_controllers()
    return utils.filter_obj(objs, service_name, identifier_type, greedy=False)


def _get_controller_type(controller_type):
    types = [ctype for ctype in canvas.list_all_controller_types() if ctype.type == controller_type]
    if types:
        return types[0]
    return None


def create_controller(pg, controller_type, properties, start, name=None):
    controller_type = _get_controller_type(controller_type)
    controller = canvas.create_controller(pg, controller_type, name)
    controller = get_controller(controller.id, 'id')
    canvas.update_controller(controller, nifi.ControllerServiceDTO(properties=properties))
    controller = get_controller(controller.id, 'id')
    canvas.schedule_controller(controller, start)
    return get_controller(controller.id, 'id')


def _create_controller(pg, service_name, props, controller_class):
    svc = get_controller(service_name)
    if svc:
        canvas.schedule_controller(svc, False)
        svc = get_controller(service_name)
        canvas.update_controller(svc, nifi.ControllerServiceDTO(properties=props))
        svc = get_controller(service_name)
        canvas.schedule_controller(svc, True)
    else:
        svc = create_controller(pg, controller_class, props, True, name=service_name)
    return svc


def create_ssl_controller(pg, service_name=DEFAULT_SSL_SERVICE_NAME,
                          truststore_location=DEFAULT_TRUSTSTORE_LOCATION,
                          truststore_password=DEFAULT_TRUSTSTORE_PASSWORD,
                          keystore_location=DEFAULT_KEYSTORE_LOCATION,
                          keystore_password=DEFAULT_KEYSTORE_PASSWORD):
    props = {
        'SSL Protocol': 'TLS',
        'Truststore Type': 'JKS',
        'Truststore Filename': truststore_location,
        'Truststore Password': truststore_password,
        'Keystore Type': 'JKS',
        'Keystore Filename': keystore_location,
        'Keystore Password': keystore_password,
        'key-password': keystore_password,
    }
    return _create_controller(pg, service_name, props, 'org.apache.nifi.ssl.StandardRestrictedSSLContextService')


def create_keytab_credentials_controller(pg, service_name=DEFAULT_KEYTAB_SERVICE_NAME,
                                         keytab_location=DEFAULT_KEYTAB_LOCATION,
                                         keytab_principal=DEFAULT_KEYTAB_PRINCIPAL):
    props = {
        'Kerberos Keytab': keytab_location,
        'Kerberos Principal': keytab_principal,
    }
    return _create_controller(pg, service_name, props, 'org.apache.nifi.kerberos.KeytabCredentialsService')


def create_kerberos_keytab_user_controller(pg, service_name=DEFAULT_KEYTAB_SERVICE_NAME,
                                           keytab_location=DEFAULT_KEYTAB_LOCATION,
                                           keytab_principal=DEFAULT_KEYTAB_PRINCIPAL):
    props = {
        'Kerberos Keytab': keytab_location,
        'Kerberos Principal': keytab_principal,
    }
    return _create_controller(pg, service_name, props, 'org.apache.nifi.kerberos.KerberosKeytabUserService')


def create_schema_registry_controller(pg, url, service_name=DEFAULT_SCHREG_SERVICE_NAME,
                                      keytab_credentials_svc=None, keytab_user_svc=None, ssl_svc=None):
    props = {
        'url': url,
    }
    if keytab_credentials_svc:
        props['kerberos-credentials-service'] = keytab_credentials_svc.id
    if keytab_user_svc:
        props['kerberos-user-service'] = keytab_user_svc.id
    if ssl_svc:
        props['ssl-context-service'] = ssl_svc.id
    return _create_controller(pg, service_name, props,
                              'com.cloudera.nifi.schemaregistry.ClouderaSchemaRegistry'
                              if get_cfm_version() >= [2, 1, 6, 0]
                              else 'org.apache.nifi.schemaregistry.hortonworks.HortonworksSchemaRegistry')


def create_json_reader_controller(pg, schema_registry_svc=None, schema_name=None,
                                  service_name=DEFAULT_JSON_READER_SERVICE_NAME):
    props = {}
    if schema_registry_svc:
        props['schema-registry'] = schema_registry_svc.id
    if schema_name:
        props['schema-access-strategy'] = 'schema-name'
        props['schema-name'] = schema_name
    else:
        props['schema-access-strategy']: 'infer-schema'
    return _create_controller(pg, service_name, props, 'org.apache.nifi.json.JsonTreeReader')


def create_json_writer_controller(pg, schema_registry_svc=None, schema_name=None, schema_write_strategy='no-schema',
                                  service_name=DEFAULT_JSON_WRITER_SERVICE_NAME):
    props = {
        'Schema Write Strategy': schema_write_strategy,
    }
    if schema_registry_svc:
        props['schema-registry'] = schema_registry_svc.id
    if schema_name:
        props['schema-access-strategy'] = 'schema-name'
        props['schema-name'] = schema_name
    else:
        props['schema-access-strategy']: 'inherit-record-schema'
    return _create_controller(pg, service_name, props, 'org.apache.nifi.json.JsonRecordSetWriter')


def create_avro_writer_controller(pg, schema_registry_svc=None, service_name=DEFAULT_AVRO_WRITER_SERVICE_NAME):
    if schema_registry_svc:
        props = {
            'schema-access-strategy': 'schema-name',
            'schema-registry': schema_registry_svc.id,
            'Schema Write Strategy': 'hwx-schema-ref-attributes',
        }
    else:
        props = {}
    return _create_controller(pg, service_name, props, 'org.apache.nifi.avro.AvroRecordSetWriter')


def create_rest_lookup_controller(pg, url, record_reader, record_path=None, service_name=DEFAULT_REST_LOOKUP_SERVICE_NAME):
    props = {
        'rest-lookup-url': url,
        'rest-lookup-record-reader': record_reader.id,
    }
    if record_path:
        props['rest-lookup-record-path'] = record_path
    return _create_controller(pg, service_name, props, 'org.apache.nifi.lookup.RestLookupService')


def create_http_context_map_controller(pg, service_name=DEFAULT_HTTP_CTX_MAP_SERVICE_NAME):
    props = {}
    return _create_controller(pg, service_name, props, 'org.apache.nifi.http.StandardHttpContextMap')


def delete_all(pg):
    canvas.schedule_process_group(pg.id, False)
    for conn in canvas.list_all_connections(pg.id):
        LOG.debug('Connection: ' + conn.id)
        try:
            canvas.delete_connection(conn, purge=True)
        except ValueError as exc:
            # Avoid failure if the connection to be deleted is not there for some reason
            if 'Unable to find connection with id' not in str(exc):
                raise exc
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
        delete_all(process_group)
        canvas.delete_process_group(process_group, force=True)
    for context in parameters.list_all_parameter_contexts():
        parameters.delete_parameter_context(context)


def get_process_group(pg_name):
    return canvas.get_process_group(pg_name, 'name')


def get_processor(processor_name, identifier_type='name'):
    return canvas.get_processor(processor_name, identifier_type, greedy=False)


def wait_for_relationships(processor, required_relationships, timeout_secs=60):
    """
    Some processors, like InvokeScriptedProcessors has dynamically-defined relationships. These can take a few
    seconds to be ready while the processor is being validated. This can lead to exceptions When trying to set a
    connection to a relationship that is not yet available. This method waits until the relationship is ready or
    until the specified timeout is reached.
    :param processor:
    :param required_relationships:
    :param timeout_secs:
    :return:
    """
    start_time = time.time()
    while time.time() - start_time < timeout_secs:
        relationships = [r.name for r in processor.component.relationships]
        if set(required_relationships) == set(required_relationships).intersection(relationships):
            return processor
        time.sleep(1)
        processor = get_processor(processor.id, 'id')
    raise RuntimeError(f'Required relationships ({required_relationships}) could not be found.'
                       f' Found only: {relationships}.')


def check_for_processor_activity(name, entity_type='processor', metric='bytes_in', timeout_secs=120, delta=None, cumulative_delta=None,
                                 absolute_value=None, is_greater_than_threshold=True):
    """
    Returns True is the processor received some data within the specified
    timeout. False, otherwise.
    :param processor_name:
    :param timeout_secs:
    :return:
    """
    assert delta is not None or absolute_value is not None, "Either delta or absolute_value must be specified."
    start = time.time()
    previous_value = value = None
    actual_delta = actual_cumulative_delta = 0
    while time.time() < start + timeout_secs:
        if entity_type == 'processor':
            ent = get_processor(name)
        elif entity_type in ['process-group', 'pg']:
            ent = get_process_group(name)
        else:
            raise RuntimeError(f'Unknown entity type {entity_type}')
        value = getattr(ent.status.aggregate_snapshot, metric)
        if isinstance(value, str):
            value = int(value)
        if previous_value is not None:
            actual_delta = value - previous_value
            actual_cumulative_delta += actual_delta
            if delta is not None and ((is_greater_than_threshold and actual_delta >= delta) or (not is_greater_than_threshold and actual_delta <= delta)):
                return True
            elif cumulative_delta is not None and ((is_greater_than_threshold and actual_cumulative_delta >= cumulative_delta) or (not is_greater_than_threshold and actual_cumulative_delta <= cumulative_delta)):
                return True
            elif absolute_value is not None and ((is_greater_than_threshold and value >= absolute_value) or (not is_greater_than_threshold and value <= absolute_value)):
                return True
        previous_value = value
        time.sleep(1)

    return False

def wait_for_data(pg_name, timeout_secs=120):
    while timeout_secs:
        pg = canvas.get_process_group(pg_name, 'name')
        if pg is None:
            break

        bytes_in = pg.status.aggregate_snapshot.bytes_in
        if bytes_in > 0:
            break
        timeout_secs -= 1
        LOG.info("Data not Flowing yet, sleeping for 3")
        time.sleep(3)

    # wait a few more seconds just to let the pipes to be primed
    time.sleep(10)


def set_environment():
    # Initialize NiFi API
    config.nifi_config.host = _get_api_url()
    config.registry_config.host = nifireg.get_api_url()
    if is_tls_enabled():
        security.set_service_ssl_context(service='nifi', ca_file=get_pem_truststore_path())
        security.set_service_ssl_context(service='registry', ca_file=get_pem_truststore_path())
        security.service_login(service='nifi', username='admin', password=get_the_pwd())
        security.service_login(service='registry', username='admin@WORKSHOP.COM', password=get_the_pwd())

    # Get NiFi root PG
    return canvas.get_process_group(canvas.get_root_pg_id(), 'id')
