#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from datetime import datetime, timedelta
from . import *

_CDSW_MODEL_NAME = 'IoT Prediction Model'
_CDSW_USERNAME = 'admin'
_CDSW_FULL_NAME = 'Workshop Admin'
_CDSW_EMAIL = 'admin@cloudera.com'
_CDSW_SESSION = None


def _get_api_url():
    return get_url_scheme() + '://cdsw.%s.nip.io/api/v1' % (get_public_ip(),)


def get_altus_api_url():
    return get_url_scheme() + '://cdsw.%s.nip.io/api/altus-ds-1' % (get_public_ip(),)


def get_model_endpoint_url():
    return get_url_scheme() + '://modelservice.cdsw.%s.nip.io/model' % (get_public_ip(),)


def _get_session():
    global _CDSW_SESSION
    if not _CDSW_SESSION:
        _CDSW_SESSION = requests.Session()
        if is_tls_enabled():
            _CDSW_SESSION.verify = get_truststore_path()
        r = _CDSW_SESSION.post(_get_api_url() + '/authenticate',
                               json={'login': _CDSW_USERNAME, 'password': get_the_pwd()}, )
        _CDSW_SESSION.headers.update({'Authorization': 'Bearer ' + r.json()['auth_token']})
    return _CDSW_SESSION


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


def _get_model_api_keys():
    resp = _get_session().get(_get_api_url() + '/users/{}/modelapikey'.format(_CDSW_USERNAME))
    if resp.status_code == requests.codes.ok:
        return resp.json()
    return None


def _delete_model_api_key(keyid):
    return _get_session().delete(_get_api_url() + '/users/{}/modelapikey/{}'.format(_CDSW_USERNAME, keyid))


def delete_all_model_api_keys():
    for key in _get_model_api_keys():
        _delete_model_api_key(key['keyid'])


def create_model_api_key():
    resp = _get_session().post(_get_api_url() + '/users/{}/modelapikey'.format(_CDSW_USERNAME),
                               json={'expiryDate': (datetime.utcnow() + timedelta(days=365)).isoformat()[:23] + 'Z'})
    if resp.status_code == requests.codes.ok:
        return resp.json()['modelapikey']
    return None


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
