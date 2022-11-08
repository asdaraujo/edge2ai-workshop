#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nipyapi import nifi, canvas, config, security, parameters
from . import *
from . import nifireg


DEFAULT_SSL_SERVICE_NAME = 'Default NiFi SSL Context Service'
DEFAULT_TRUSTSTORE_LOCATION = '/opt/cloudera/security/jks/truststore.jks'
DEFAULT_TRUSTSTORE_PASSWORD = get_the_pwd()
DEFAULT_KEYSTORE_LOCATION = '/opt/cloudera/security/jks/keystore.jks'
DEFAULT_KEYSTORE_PASSWORD = get_the_pwd()

DEFAULT_KEYTAB_SERVICE_NAME = 'KeytabCredentialsService'
DEFAULT_KEYTAB_LOCATION = '/keytabs/admin.keytab'
DEFAULT_KEYTAB_PRINCIPAL = 'admin'

DEFAULT_SCHREG_SERVICE_NAME = 'Schema Registry'
DEFAULT_JSON_READER_SERVICE_NAME = 'JsonTreeReader'
DEFAULT_JSON_WRITER_SERVICE_NAME = 'JsonRecordSetWriter'
DEFAULT_AVRO_WRITER_SERVICE_NAME = 'AvroRecordSetWriter'
DEFAULT_REST_LOOKUP_SERVICE_NAME = 'RestLookupService'
DEFAULT_HTTP_CTX_MAP_SERVICE_NAME = 'StandardHttpContextMap'


def _get_port():
    return '8443' if is_tls_enabled() else '8080'


def get_url():
    return '%s://%s:%s/nifi' % (get_url_scheme(), get_hostname(), _get_port())


def _get_api_url():
    return '%s://%s:%s/nifi-api' % (get_url_scheme(), get_hostname(), _get_port())


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


def _get_controller_type(controller_type):
    types = [ctype for ctype in canvas.list_all_controller_types() if ctype.type == controller_type]
    if types:
        return types[0]
    return None


def create_controller(pg, controller_type, properties, start, name=None):
    controller_type = _get_controller_type(controller_type)
    controller = canvas.create_controller(pg, controller_type, name)
    controller = canvas.get_controller(controller.id, 'id')
    canvas.update_controller(controller, nifi.ControllerServiceDTO(properties=properties))
    controller = canvas.get_controller(controller.id, 'id')
    canvas.schedule_controller(controller, start)
    return canvas.get_controller(controller.id, 'id')


def _create_controller(pg, service_name, props, controller_class):
    svc = canvas.get_controller(service_name, 'name')
    if svc:
        canvas.schedule_controller(svc, False)
        svc = canvas.get_controller(service_name, 'name')
        canvas.update_controller(svc, nifi.ControllerServiceDTO(properties=props))
        svc = canvas.get_controller(service_name, 'name')
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


def create_keytab_controller(pg, service_name=DEFAULT_KEYTAB_SERVICE_NAME,
                             keytab_location=DEFAULT_KEYTAB_LOCATION,
                             keytab_principal=DEFAULT_KEYTAB_PRINCIPAL):
    props = {
        'Kerberos Keytab': keytab_location,
        'Kerberos Principal': keytab_principal,
    }
    return _create_controller(pg, service_name, props, 'org.apache.nifi.kerberos.KeytabCredentialsService')


def create_schema_registry_controller(pg, url, service_name=DEFAULT_SCHREG_SERVICE_NAME,
                                      keytab_svc=None, ssl_svc=None):
    props = {
        'url': url,
    }
    if keytab_svc:
        props['kerberos-credentials-service'] = keytab_svc.id
    if ssl_svc:
        props['ssl-context-service'] = ssl_svc.id
    return _create_controller(pg, service_name, props,
                              'org.apache.nifi.schemaregistry.hortonworks.HortonworksSchemaRegistry')


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
        delete_all(process_group)
        canvas.delete_process_group(process_group, force=True)
    for context in parameters.list_all_parameter_contexts():
        parameters.delete_parameter_context(context)


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
        security.set_service_ssl_context(service='nifi', ca_file=get_truststore_path())
        security.set_service_ssl_context(service='registry', ca_file=get_truststore_path())
        security.service_login(service='nifi', username='admin', password=get_the_pwd())
        security.service_login(service='registry', username='admin@WORKSHOP.COM', password=get_the_pwd())

    # Get NiFi root PG
    return canvas.get_process_group(canvas.get_root_pg_id(), 'id')
