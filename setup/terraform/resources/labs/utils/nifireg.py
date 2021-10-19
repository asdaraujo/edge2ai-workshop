#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nipyapi import versioning
from nipyapi.registry import BucketFlowsApi

from . import *


def _get_port():
    return '18433' if is_tls_enabled() else '18080'


def get_url():
    return '%s://%s:%s' % (get_url_scheme(), get_hostname(), _get_port())


def get_api_url():
    return '%s://%s:%s/nifi-registry-api' % (get_url_scheme(), get_hostname(), _get_port())


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


def _api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = get_api_url() + endpoint
    auth = None
    return api_request(method, url, expected_code, auth=auth, **kwargs)


def _api_delete(endpoint, expected_code=requests.codes.ok, **kwargs):
    return _api_request('DELETE', endpoint, expected_code, **kwargs)


def delete_flows(identifier, identifier_type='name'):
    bucket = versioning.get_registry_bucket(identifier, identifier_type)
    if bucket:
        for flow in versioning.list_flows_in_bucket(bucket.identifier):
            BucketFlowsApi().delete_flow(flow.bucket_identifier, flow.identifier)
