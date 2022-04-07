#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
from . import *
from . import cdsw

_DATAVIZ_SESSION = None
_DATAVIZ_CSRF_TOKEN = None
_DATAVIZ_USER = 'admin'

_CSRF_REGEXPS = [
    r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"',
    r'.*"csrfmiddlewaretoken": "([^"]*)"',
    r'.*\.csrf_token\("([^"]*)"\)'
]


def _get_api_url():
    return '{}://viz.{}/arc'.format(get_url_scheme(), cdsw.get_cdsw_domain_name())


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


def _api_call(func, path, data=None, files=None, headers=None):
    global _DATAVIZ_CSRF_TOKEN
    if not headers:
        headers = {}
    if _DATAVIZ_CSRF_TOKEN:
        headers['X-CSRFToken'] = _DATAVIZ_CSRF_TOKEN
    if not 'Content-Type' in headers:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    url = _get_api_url() + path
    resp = func(url, data=data, headers=headers, files=files)
    if resp.status_code != requests.codes.ok:
        raise RuntimeError("Call to {} returned status {}. Text: {}".format(
            url, resp.status_code, resp.text))

    token = _get_csrf_token(resp.text, quiet=True)
    if token:
        _DATAVIZ_CSRF_TOKEN = token

    return resp


def _api_get(path, data=None, headers=None):
    return _api_call(_get_session().get, path, data=data, headers=headers)


def _api_post(path, data=None, files=None, headers=None):
    return _api_call(_get_session().post, path, data=data, files=files, headers=headers)


def _api_delete(path, data=None):
    return _api_call(_get_session().delete, path, data=data)


def _get_session():
    global _DATAVIZ_SESSION
    if not _DATAVIZ_SESSION:
        _DATAVIZ_SESSION = requests.Session()
        if is_tls_enabled():
            _DATAVIZ_SESSION.verify = get_truststore_path()

        _api_get('/apps/login')
        _api_post('/apps/login?', {'next': '', 'username': _DATAVIZ_USER, 'password': get_the_pwd()})
    return _DATAVIZ_SESSION


# APPS API

def create_api_key():
    data = {
        'username': 'admin',
        'apikey': 'New key will be generated on save',
        'active': 'true',
        'expires': 'Invalid date',
    }
    resp = _api_post('/apps/apikey_api', data)
    return resp.json()['apikey'], resp.json()['secret_apikey']


def delete_api_key(apikey):
    data = {
        'apikeys_list': '["{}"]'.format(apikey),
    }
    resp = _api_delete('/apps/apikey_api', data)


def get_users():
    resp = _api_get(_get_api_url() + '/apps/users_api',
                    headers={
                        'Content-Type': 'application/json',
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


def create_connection(conn_type, conn_name, params):
    data = {
        'dataconnection_type': conn_type,
        'dataconnection_name': conn_name,
        'dataconnection_info': json.dumps({'PARAMS': params}),
        'do_validate': True
    }
    resp = _api_post('/datasets/dataconnection', data)


def get_connection(conn_name):
    resp = _api_get('/datasets/dataconnection')
    conns = [c for c in resp.json() if c['name'] == conn_name]
    if conns:
        return conns[0]
    return None


def delete_connection(dc_id=None, dc_name=None):
    assert dc_id is not None or dc_name is not None, 'One of "dc_id" or "dc_name" must be specified.'
    assert dc_id is None or dc_name is None, 'Only one of "dc_id" or "dc_name" can be specified.'
    if dc_id is None:
        conn = get_connection(dc_name)
        if conn:
            dc_id = conn['id']
    if dc_id:
        _api_delete('/datasets/dataconnection/{}'.format(dc_id))


def create_dataset(data):
    resp = _api_post('/datasets/dataset', data)


def delete_dataset(ds_id=None, ds_name=None, dc_name=None):
    assert ds_id is not None or ds_name is not None or dc_name is not None,\
        'One of "ds_id", "ds_name" or "dc_name" must be specified.'
    assert (0 if ds_id is None else 1) + (0 if ds_name is None else 1) + (0 if dc_name is None else 1),\
        'Only one of "ds_id", "ds_name" or "dc_name" can be specified.'
    if ds_id is not None:
        ds_ids = [ds_id]
    elif ds_name is not None:
        ds = get_datasets(ds_name=ds_name)
        assert len(ds) <= 1, 'More than one dataset found with the same name'
        ds_ids = [d['id'] for d in ds]
    else:
        ds_ids = [d['id'] for d in get_datasets(conn_name=dc_name)]
    for ds_id in ds_ids:
        _api_delete('/datasets/dataset/{}?delete_table=false'.format(ds_id))


def get_datasets(ds_name=None, conn_name=None):
    resp = _api_get('/datasets/dataset')
    return [d for d in resp.json()
            if (ds_name is None or d['name'] == ds_name)
            and (conn_name is None or d['dc_name'] == conn_name)]


def import_artifacts(dc_name, file_name):
    apikey = None
    try:
        apikey, secret = create_api_key()
        headers = {'AUTHORIZATION': 'apikey ' + secret}
        payload = {'dry_run': False, 'dataconnection_name': dc_name}
        files = {'import_file': open(file_name, 'r')}
        _api_post('/migration/api/import/', files=files, data=payload, headers=headers)
    finally:
        if apikey:
            delete_api_key(apikey)


def _get_model():
    r = _get_session().post(get_altus_api_url() + '/models/list-models',
                            json={'projectOwnerName': 'admin',
                                  'latestModelDeployment': True,
                                  'latestModelBuild': True})
    models = [m for m in r.json() if m['name'] == 'IoT Prediction Model']
    model = None
    for m in models:
        if m['name'] == _CDSW_MODEL_NAME:
            model = m
    return model


def _deploy_model(model):
    _get_session().post(get_altus_api_url() + '/models/deploy-model', json={
        'modelBuildId': model['latestModelBuild']['id'],
        'memoryMb': 4096,
        'cpuMillicores': 1000,
    })


def get_model_access_key():
    while True:
        model = _get_model()
        if not model:
            status = 'not created yet'
        elif 'latestModelDeployment' not in model or 'status' not in model['latestModelDeployment']:
            status = 'unknown'
        elif model['latestModelDeployment']['status'] == 'deployed':
            return model['accessKey']
        elif model['latestModelDeployment']['status'] == 'stopped':
            _deploy_model(model)
            status = 'stopped'
        else:
            status = model['latestModelDeployment']['status']
        LOG.info('Model not deployed yet. Model status is currently "%s". Waiting for deployment to finish.', status)
        time.sleep(10)
