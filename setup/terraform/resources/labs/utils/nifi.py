#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nipyapi import nifi, canvas, config, security
from . import *
from . import nifireg


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


def update_connection(source, destination, new_destination):
    conn = [c for c in canvas.list_all_connections()
            if c.source_id == source.id and c.destination_id == destination.id][0]
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
