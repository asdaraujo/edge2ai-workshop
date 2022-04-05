#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from requests_gssapi import HTTPSPNEGOAuth

from . import *


def _get_port():
    return '7790' if is_tls_enabled() else '7788'


def get_api_url():
    return '%s://%s:%s/api/v1' % (get_url_scheme(), get_hostname(), _get_port())


def _api_request(method, endpoint, **kwargs):
    url = get_api_url() + endpoint
    if is_tls_enabled():
        auth = HTTPSPNEGOAuth()
    else:
        auth = None
    return api_request(method, url, auth=auth, **kwargs)


def _api_get(endpoint, **kwargs):
    return _api_request('GET', endpoint, **kwargs)


def _api_post(endpoint, **kwargs):
    return _api_request('POST', endpoint, **kwargs)


def _api_delete(endpoint, **kwargs):
    return _api_request('DELETE', endpoint, **kwargs)


def get_versions(name):
    endpoint = '/schemaregistry/schemas/{name}/versions'.format(name=name)
    resp = _api_get(endpoint, headers={'Content-Type': 'application/json'})
    return resp.json()['entities']


def get_all_schemas():
    endpoint = '/schemaregistry/schemas'
    resp = _api_get(endpoint, headers={'Content-Type': 'application/json'})
    return resp.json()['entities']


def delete_all_schemas():
    for schema in get_all_schemas():
        delete_schema(schema['schemaMetadata']['name'])


def delete_schema(name):
    endpoint = '/schemaregistry/schemas/{name}'.format(name=name)
    _api_delete(endpoint, headers={'Content-Type': 'application/json'})
    LOG.debug('Schema %s deleted.', name)


def create_schema(name, description, schema_text):
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
    _api_post(endpoint, expected_codes=[requests.codes.created],
              headers={'Content-Type': 'application/json'}, json=body)
    _create_schema_version(name, schema_text)


def _create_schema_version(name, schema_text):
    endpoint = '/schemaregistry/schemas/{name}/versions'.format(name=name)
    body = {
        'schemaText': schema_text
    }
    _api_post(endpoint, expected_codes=[requests.codes.created],
              headers={'Content-Type': 'application/json'}, json=body)
