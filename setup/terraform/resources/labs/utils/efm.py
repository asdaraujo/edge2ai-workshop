#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
from . import *

_AGENT_MANIFESTS = None


def _get_api_url():
    return '%s://%s:10088/efm/api' % ('http', get_hostname(),)


def _api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _get_api_url() + endpoint
    return api_request(method, url, expected_code, **kwargs)


def _api_get(endpoint, expected_code=requests.codes.ok, **kwargs):
    return _api_request('GET', endpoint, expected_code, **kwargs)


def _api_post(endpoint, expected_code=requests.codes.ok, **kwargs):
    return _api_request('POST', endpoint, expected_code, **kwargs)


def _api_delete(endpoint, expected_code=requests.codes.ok, **kwargs):
    return _api_request('DELETE', endpoint, expected_code, **kwargs)


def _get_client_id():
    resp = _api_get('/designer/client-id')
    return resp.text


def _get_agent_manifests():
    global _AGENT_MANIFESTS
    if not _AGENT_MANIFESTS:
        resp = _api_get('/agent-manifests')
        _AGENT_MANIFESTS = resp.json()
    return _AGENT_MANIFESTS


def get_flow(agent_class):
    resp = _api_get('/designer/flows')
    json = resp.json()
    assert ('elements' in json)
    assert (len(json['elements']) == 1)
    flow = json['elements'][0]
    return flow['identifier'], flow['rootProcessGroupIdentifier']


def _get_processor_bundle(processor_type):
    for manifest in _get_agent_manifests():
        for bundle in manifest['bundles']:
            for processor in bundle['componentManifest']['processors']:
                if processor['type'] == processor_type:
                    return {
                        'group': processor['group'],
                        'artifact': processor['artifact'],
                        'version': processor['version'],
                    }
    raise RuntimeError('Processor type %s not found in agent manifest.' % (processor_type,))


def create_processor(flow_id, pg_id, name, processor_type, position, properties, auto_terminate=None):
    endpoint = '/designer/flows/{flowId}/process-groups/{pgId}/processors'.format(flowId=flow_id, pgId=pg_id)
    body = {
        'revision': {
            'clientId': _get_client_id(),
            'version': 0
        },
        'componentConfiguration': {
            'name': name,
            'type': processor_type,
            'bundle': _get_processor_bundle(processor_type),
            'position': {
                'x': position[0],
                'y': position[1]
            },
            'properties': properties,
            'autoTerminatedRelationships': auto_terminate,
        }
    }
    resp = _api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()['componentConfiguration']['identifier']


def create_remote_processor_group(flow_id, pg_id, name, rpg_url, transport_protocol, position):
    endpoint = '/designer/flows/{flowId}/process-groups/{pgId}/remote-process-groups'.format(flowId=flow_id, pgId=pg_id)
    body = {
        'revision': {
            'clientId': _get_client_id(),
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
    resp = _api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()['componentConfiguration']['identifier']


def _get_all_by_type(flow_id, obj_type):
    endpoint = '/designer/flows/{flowId}'.format(flowId=flow_id)
    resp = _api_get(endpoint, headers={'Content-Type': 'application/json'})
    obj_type_alt = re.sub(r'[A-Z]', lambda x: '-' + x.group(0).lower(), obj_type)
    for obj in resp.json()['flowContent'][obj_type]:
        endpoint = '/designer/flows/{flowId}/{objType}/{objId}'.format(flowId=flow_id, objType=obj_type_alt,
                                                                       objId=obj['identifier'])
        resp = _api_get(endpoint, headers={'Content-Type': 'application/json'})
        yield resp.json()


def delete_by_type(flow_id, obj, obj_type):
    obj_id = obj['componentConfiguration']['identifier']
    version = obj['revision']['version']
    client_id = _get_client_id()
    obj_type_alt = re.sub(r'[A-Z]', lambda x: '-' + x.group(0).lower(), obj_type)
    endpoint = '/designer/flows/{flowId}/{objType}/{objId}?version={version}&clientId={clientId}'.format(
        flowId=flow_id,
        objType=obj_type_alt,
        objId=obj_id,
        version=version,
        clientId=client_id)
    _api_delete(endpoint, headers={'Content-Type': 'application/json'})
    LOG.debug('Object of type %s (%s) deleted.', obj_type, obj_id)


def delete_all(flow_id):
    for obj_type in ['connections', 'remoteProcessGroups', 'processors', 'inputPorts', 'outputPorts']:
        for conn in _get_all_by_type(flow_id, obj_type):
            delete_by_type(flow_id, conn, obj_type)


def create_connection(flow_id, pg_id, source_id, source_type, destination_id, destination_type, relationships,
                      source_port=None, destination_port=None,
                      name=None, flow_file_expiration=None):
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
            'clientId': _get_client_id(),
            'version': 0
        },
        'componentConfiguration': {
            'source': _get_endpoint(source_id, source_type, source_port),
            'destination': _get_endpoint(destination_id, destination_type, destination_port),
            'selectedRelationships': relationships,
            'name': name,
            'flowFileExpiration': flow_file_expiration,
            'backPressureObjectThreshold': None,
            'backPressureDataSizeThreshold': None,
        }
    }
    resp = _api_post(endpoint, requests.codes.created, headers={'Content-Type': 'application/json'}, json=body)
    return resp.json()


def publish_flow(flow_id, comments):
    endpoint = '/designer/flows/{flowId}/publish'.format(flowId=flow_id)
    body = {
        'comments': comments,
    }
    _api_post(endpoint, headers={'Content-Type': 'application/json'}, json=body)
