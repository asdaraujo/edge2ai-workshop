#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from . import *

_CDSW_PROJECT_NAME = 'Edge2AI Workshop'
_CDSW_MODEL_NAME = 'IoT Prediction Model'
_VIZ_USERNAME = 'admin'
_CDSW_FULL_NAME = 'Workshop Admin'
_CDSW_EMAIL = 'admin@cloudera.com'
_VIZ_SESSION = None
_VIZ_PROJECT_NAME = 'VizApps Workshop'

_CSRF_REGEXPS = [
    r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"',
    r'.*"csrfmiddlewaretoken": "([^"]*)"',
    r'.*\.csrf_token\("([^"]*)"\)'
]


class VizAppsInvalidLoginAttempt(RuntimeError):
    def __init__(self, msg=None):
        super().__init__(msg)


def _api_get(url, **kwargs):
    return api_get(url, session=_get_session(), **kwargs)


def _api_post(url, **kwargs):
    return api_post(url, session=_get_session(), **kwargs)


def _api_put(url, **kwargs):
    return api_put(url, session=_get_session(), **kwargs)


def _api_patch(url, **kwargs):
    return api_patch(url, session=_get_session(), **kwargs)


def _get_session():
    global _VIZ_SESSION
    if not _VIZ_SESSION:
        _VIZ_SESSION = requests.Session()
        if is_tls_enabled():
            _VIZ_SESSION.verify = get_truststore_path()
    return _VIZ_SESSION


def _get_api_url():
    return get_url_scheme() + '://viz.cdsw.%s.nip.io/arc/apps' % (get_public_ip(),)


def _get_csrf_token(txt, quiet=False):
    token = None
    for regexp in _CSRF_REGEXPS:
        m = re.match(regexp, txt, flags=re.DOTALL)
        if m:
            token = m.groups()[0]
            break
    else:
        if not quiet:
            raise RuntimeError("Cannot find CSRF token.")
    return token


def _get_vizapps_csrf_token(username=_VIZ_USERNAME, password=None):
    if password is None:
        password = get_the_pwd()
    resp = _api_get(_get_api_url() + '/login')
    token = _get_csrf_token(resp.text)
    resp = _api_post(_get_api_url() + '/login?',
                     data='csrfmiddlewaretoken=' + token + '&next=&username=' + username + '&password=' + password,
                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
    token = _get_csrf_token(resp.text, quiet=True)
    if token is None or 'Invalid login' in resp.text:
        raise VizAppsInvalidLoginAttempt()
    return token


def get_users():
    resp = _api_get(_get_api_url() + '/users_api',
                    headers={
                        'Content-Type': 'application/json',
                        'X-CSRFToken': _get_vizapps_csrf_token(),
                    })
    if resp.status_code == requests.codes.ok:
        return resp.json()
    return []


def get_user(username):
    users = get_users()
    for user in users:
        if user['username'] == username:
            return user
    return {}
