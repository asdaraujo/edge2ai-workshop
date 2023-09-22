#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from datetime import datetime, timedelta

import requests

from . import *

CM_CREDS = ('admin', get_the_pwd())

_API_VERSION = None
_CLUSTER_NAME = None


def _get_cm_port():
    return 7183 if is_tls_enabled() else 7180


def _get_cm_api_version_url():
    return get_url_scheme() + '://{}:{}/api/version'.format(get_hostname(), _get_cm_port())


def _get_cm_api_version():
    global _API_VERSION
    if not _API_VERSION:
        return api_request('GET', _get_cm_api_version_url(), auth=CM_CREDS).text
    return _API_VERSION


def _get_cm_api_url():
    return get_url_scheme() + '://{}:{}/api/{}'.format(get_hostname(), _get_cm_port(), _get_cm_api_version())


def _api_request(method, endpoint, expected_codes=None, **kwargs):
    url = _get_cm_api_url() + endpoint
    return api_request(method, url, expected_codes, auth=CM_CREDS, **kwargs)


def _get_cluster_name():
    global _CLUSTER_NAME
    if not _CLUSTER_NAME:
        clusters = _api_request('GET', '/clusters').json()
        assert len(clusters['items']) == 1
        _CLUSTER_NAME = clusters['items'][0]['name']
    return _CLUSTER_NAME


def _wait_for_command(cmds, timeout_secs=300):
    if not isinstance(cmds, list):
        cmds = [cmds]
    cmd = None
    for cmd in [c for c in cmds if c]:
        while timeout_secs > 0:
            if not cmd['active']:
                break
            timeout_secs -= 1
            time.sleep(1)
            cmd = get_command(cmd['id'])
    return cmd


def _execute_service_cmd(service_name, cmd, wait=True, ok_not_found=True):
    resp = _api_request('POST', '/clusters/{}/services/{}/commands/{}'.format(_get_cluster_name(), service_name, cmd),
                        expected_codes=[requests.codes.ok, requests.codes.not_found])
    if resp.status_code == requests.codes.not_found:
        if ok_not_found:
            return None
        raise RuntimeError("Service {} not found when trying to execute command {}.".format(service_name, cmd))
    cmd = resp.json()
    return _wait_for_command(cmd, timeout_secs=300 if wait else 0)


def _apilize_config(config):
    if config:
        config = [{'name': k, 'value': v} for k, v in config.items()]
    else:
        config = []
    return {
        'items': config
    }


def get_host_ref():
    hosts = _api_request('GET', '/hosts'.format(_get_cluster_name())).json()
    if len(hosts['items']) == 0:
        raise RuntimeError('Cluster has no nodes.')
    if len(hosts['items']) > 1:
        raise RuntimeError('Cluster has more than 1 node.')
    host = hosts['items'][0]
    return {'hostId': host['hostId'], 'hostname': host['hostname']}


def get_product_version(product, stage='ACTIVATED'):
    products = _api_request('GET', '/clusters/{}/parcels'.format(_get_cluster_name())).json()
    selected_version = [p for p in products['items'] if p['product'] == product and p['stage'] == stage]
    assert len(selected_version) == 1
    return selected_version[0]['version']


def get_command(cmd_id):
    return _api_request('GET', '/commands/{}'.format(cmd_id)).json()


def get_services(service_type=None):
    services = _api_request('GET', '/clusters/{}/services'.format(_get_cluster_name())).json()
    selected_services = [s for s in services['items'] if service_type is None or s['type'] == service_type]
    return selected_services


def get_rcgs(service_name, role_type=None):
    rcgs = _api_request('GET', '/clusters/{}/services/{}/roleConfigGroups'.format(_get_cluster_name(),
                                                                                  service_name)).json()
    return [r for r in rcgs['items'] if r['roleType'] == role_type]


def stop_service(service_name, wait=True):
    return _execute_service_cmd(service_name, 'stop', wait)


def start_service(service_name, wait=True):
    return _execute_service_cmd(service_name, 'start', wait)


def restart_service(service_name, wait=True):
    return _execute_service_cmd(service_name, 'restart', wait)


def restart_stale_services(wait=True):
    cmds = []
    for svc in get_services():
        if svc['configStalenessStatus'] != 'FRESH':
            cmds.append(restart_service(svc['name'], wait=False))
    _wait_for_command(cmds)


def deploy_client_config(wait=True, force=True):
    if not force:
        for svc in get_services():
            if svc['clientConfigStalenessStatus'] != 'FRESH':
                break
        else:
            return None

    cmd = _api_request('POST', '/clusters/{}/commands/deployClientConfig'.format(_get_cluster_name())).json()
    return _wait_for_command(cmd, timeout_secs=300 if wait else 0)


def delete_service(service_name):
    return _api_request('DELETE', '/clusters/{}/services/{}'.format(_get_cluster_name(), service_name),
                        expected_codes=[requests.codes.ok, requests.codes.not_found])


def add_service(service_name, service_type, roles, configs=None, display_name=None):
    if not display_name:
        display_name = service_name
    if configs and 'SERVICE-WIDE' in configs:
        service_config = [{'name': k, 'value': v} for k, v in configs['SERVICE-WIDE'].items()]
    else:
        service_config = []
    roles = [{'type': r, 'hostRef': get_host_ref()} for r in roles]
    service_spec = {
        'items': [
            {
                'name': service_name,
                'type': service_type,
                'displayName': display_name,
                'config': {
                    'items': service_config
                },
                'roles': roles
            }
        ]
    }
    svc = _api_request('POST', '/clusters/{}/services'.format(_get_cluster_name()), json=service_spec)

    for role_type, cfg in configs.items():
        if role_type == 'SERVICE-WIDE':
            continue
        update_rcg_config(service_name, role_type, cfg)


def update_service_config(service_name, config):
    return _api_request('PUT', '/clusters/{}/services/{}/config'.format(_get_cluster_name(), service_name),
                        json=_apilize_config(config))


def update_rcg_config(service_name, role_type, config):
    rcgs = get_rcgs(service_name, role_type)
    if not rcgs:
        raise RuntimeError('Could not find role config group of type {} for service {}.'.format(role_type,
                                                                                                service_name))
    elif len(rcgs) > 1:
        raise RuntimeError('Found multiple role config groups ({}) of type {} for service {}.'.format(
            len(rcgs), role_type, service_name))
    rcg = rcgs[0]
    return _api_request('PUT', '/clusters/{}/services/{}/roleConfigGroups/{}/config'.format(_get_cluster_name(),
                                                                                            service_name,
                                                                                            rcg['name']),
                        json=_apilize_config(config))


def delete_peer_kafka_external_account(account_name):
    return _api_request('DELETE', '/externalAccounts/delete/{}'.format(account_name),
                        expected_codes=[requests.codes.ok, requests.codes.not_found, requests.codes.bad_request])


def create_peer_kafka_external_account(account_name, peer_hostname):
    kafka_account = {
        'name': account_name,
        'displayName': account_name,
        'typeName': 'KAFKA_SERVICE',
        'accountConfigs': {
            'items': [
                {
                    'name': 'kafka_bootstrap_servers',
                    'value': kafka.get_bootstrap_servers(peer_hostname)
                }, {
                    'name': 'kafka_security_protocol',
                    'value': kafka.get_security_protocol()
                }
            ]
        }}

    if is_kerberos_enabled():
        kafka_account['accountConfigs']['items'].extend([
            {
                'name': 'kafka_jaas_secret1',
                'value': get_the_pwd()
            }, {
                'name': 'kafka_jaas_template',
                'value': 'org.apache.kafka.common.security.plain.PlainLoginModule'
                         ' required username="admin"'
                         ' password="##JAAS_SECRET_1##"; '
            }, {
                'name': 'kafka_sasl_mechanism',
                'value': 'PLAIN'
            }
        ])

    if is_tls_enabled():
        kafka_account['accountConfigs']['items'].extend([
            {
                'name': 'kafka_truststore_password',
                'value': '${THE_PWD}'
            }, {
                'name': 'kafka_truststore_path',
                'value': '${TRUSTSTORE_JKS}'
            }, {
                'name': 'kafka_truststore_type',
                'value': 'JKS'
            }
        ])

    return _api_request('POST', '/externalAccounts/create', json=kafka_account)
