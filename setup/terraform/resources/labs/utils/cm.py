#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from datetime import datetime, timedelta
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


def _api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _get_cm_api_url() + endpoint
    return api_request(method, url, expected_code, auth=CM_CREDS, **kwargs)


def _get_cluster_name():
    global _CLUSTER_NAME
    if not _CLUSTER_NAME:
        clusters = _api_request('GET', '/clusters').json()
        assert len(clusters['items']) == 1
        _CLUSTER_NAME = clusters['items'][0]['name']
    return _CLUSTER_NAME


def get_product_version(product, stage='ACTIVATED'):
    products = _api_request('GET', '/clusters/{}/parcels'.format(_get_cluster_name())).json()
    selected_version = [p for p in products['items'] if p['product'] == product and p['stage'] == stage]
    assert len(selected_version) == 1
    return selected_version[0]['version']
