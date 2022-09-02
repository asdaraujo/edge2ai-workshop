#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
from requests_gssapi import HTTPSPNEGOAuth

from . import *


def _get_port():
    return '8587' if is_tls_enabled() else '8585'


def _get_api_url():
    return '%s://%s:%s' % (get_url_scheme(), get_hostname(), _get_port())


def _api_request(method, endpoint, expected_codes=None, **kwargs):
    url = _get_api_url() + endpoint
    if is_tls_enabled():
        auth = HTTPSPNEGOAuth()
    else:
        auth = None
    return api_request(method, url, expected_codes, auth=auth, **kwargs)


def api_get(endpoint, expected_codes=None, **kwargs):
    return _api_request('GET', endpoint, expected_codes, **kwargs)


def get_smm_version():
    resp = api_get('/api/v1/admin/version')
    assert resp.status_code == requests.codes.ok
    version_info = resp.json()
    assert version_info and 'version' in version_info
    return [int(n) for n in re.split(r'[^0-9]', version_info['version'])]


def get_aggregation_api_prefix():
    if get_smm_version() >= [2, 3, 0]:
        return '/api/v2'
    else:
        return '/api/v1'
