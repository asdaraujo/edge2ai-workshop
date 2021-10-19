#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from requests_gssapi import HTTPSPNEGOAuth

from . import *


def _get_port():
    return '8587' if is_tls_enabled() else '8585'


def _get_api_url():
    return '%s://%s:%s' % (get_url_scheme(), get_hostname(), _get_port())


def _api_request(method, endpoint, expected_code=requests.codes.ok, **kwargs):
    url = _get_api_url() + endpoint
    if is_tls_enabled():
        auth = HTTPSPNEGOAuth()
    else:
        auth = None
    return api_request(method, url, expected_code, auth=auth, **kwargs)


def api_get(endpoint, expected_code=requests.codes.ok, **kwargs):
    return _api_request('GET', endpoint, expected_code, **kwargs)
