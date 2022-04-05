#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from datetime import timedelta
from . import *

_CDSW_PROJECT_NAME = 'Edge2AI Workshop'
_CDSW_MODEL_NAME = 'IoT Prediction Model'
_CDSW_USERNAME = 'admin'
_CDSW_FULL_NAME = 'Workshop Admin'
_CDSW_EMAIL = 'admin@cloudera.com'
_CDSW_SESSION = None
_VIZ_PROJECT_NAME = 'VizApps Workshop'


def _get_api_url():
    return get_url_scheme() + '://cdsw.%s.nip.io/api/v1' % (get_public_ip(),)


def get_altus_api_url():
    return get_url_scheme() + '://cdsw.%s.nip.io/api/altus-ds-1' % (get_public_ip(),)


def get_model_endpoint_url():
    return get_url_scheme() + '://modelservice.cdsw.%s.nip.io/model' % (get_public_ip(),)


def get_session():
    global _CDSW_SESSION
    if not _CDSW_SESSION:
        _CDSW_SESSION = requests.Session()
        if is_tls_enabled():
            _CDSW_SESSION.verify = get_truststore_path()
        r = _CDSW_SESSION.post(_get_api_url() + '/authenticate',
                               json={'login': _CDSW_USERNAME, 'password': get_the_pwd()}, )
        _CDSW_SESSION.headers.update({'Authorization': 'Bearer ' + r.json()['auth_token']})
    return _CDSW_SESSION


def _api_get(url, **kwargs):
    return api_get(url, session=get_session(), **kwargs)


def _api_post(url, **kwargs):
    return api_post(url, session=get_session(), **kwargs)


def _api_put(url, **kwargs):
    return api_put(url, session=get_session(), **kwargs)


def _api_patch(url, **kwargs):
    return api_patch(url, session=get_session(), **kwargs)


def get_release():
    resp = _api_get(_get_api_url() + '/site/stats')
    release_str = [c['value'] for c in resp.json() if c['key'] == 'config.release'][0]
    return [int(v) for v in release_str.split('.')]


def get_model(model_name=_CDSW_MODEL_NAME):
    r = _api_post(get_altus_api_url() + '/models/list-models',
                  json={'projectOwnerName': 'admin',
                        'latestModelDeployment': True,
                        'latestModelBuild': True})
    models = [m for m in r.json() if m['name'] == model_name]
    if models:
        return models[0]
    return {}


def get_project(name=_CDSW_PROJECT_NAME, project_id=None):
    if (not name and not project_id) or (name and project_id):
        raise RuntimeError("Must specify either name or id, but not both.")
    resp = _api_get(_get_api_url() + '/users/admin/projects')
    for proj in resp.json():
        if (name and proj['name'] == name) or (project_id and proj['id'] == project_id):
            return proj
    return {}


def _deploy_model(model):
    get_session().post(get_altus_api_url() + '/models/deploy-model', json={
        'modelBuildId': model['latestModelBuild']['id'],
        'memoryMb': 4096,
        'cpuMillicores': 1000,
    })


def get_model_api_keys():
    # /users/{}/modelapikey has been deprecated in CDSW 1.10
    resp = get_session().get(_get_api_url() + '/users/{}/modelapikey'.format(_CDSW_USERNAME))
    if resp.status_code == requests.codes.ok and resp.json():
        return resp.json()

    resp = get_session().get(_get_api_url() + '/users/{}/apikey'.format(_CDSW_USERNAME))
    if resp.status_code == requests.codes.ok:
        return resp.json()
    return []


def get_model_api_key(keyid):
    api_keys = get_model_api_keys()
    for api_key in api_keys:
        if api_key['keyid'] == keyid:
            return api_key
    return {}


def delete_model_api_key(keyid):
    # /users/{}/modelapikey has been deprecated in CDSW 1.10
    resp = get_session().delete(_get_api_url() + '/users/{}/apikey/{}'.format(_CDSW_USERNAME, keyid))
    if resp.status_code == requests.codes.ok and resp.json():
        return resp

    resp_old = get_session().delete(_get_api_url() + '/users/{}/modelapikey/{}'.format(_CDSW_USERNAME, keyid))
    if resp_old.status_code == requests.codes.ok:
        return resp_old
    return resp


def delete_all_model_api_keys():
    for key in get_model_api_keys():
        delete_model_api_key(key['keyid'])


def create_model_api_key(return_object=False):
    # /users/{}/modelapikey has been deprecated in CDSW 1.10
    api_key = {}
    resp = get_session().post(_get_api_url() + '/users/{}/modelapikey'.format(_CDSW_USERNAME),
                              json={'expiryDate': (datetime.utcnow() + timedelta(days=365)).isoformat()[:23] + 'Z'})
    if resp.status_code == requests.codes.ok and resp.json():
        api_key = resp.json()
    else:
        resp = get_session().post(
            _get_api_url() + '/users/{}/apikey'.format(_CDSW_USERNAME),
            json={'expiryDate': (datetime.utcnow() + timedelta(days=365)).isoformat()[:23] + 'Z'})
        if resp.status_code == requests.codes.ok:
            api_key = resp.json()

    if api_key and not return_object:
        if 'modelapikey' in api_key:
            return api_key['modelapikey']
        elif 'apiKey' in api_key:
            return api_key['apiKey']
        return None

    return api_key


def get_model_access_key():
    while True:
        model = get_model()
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


def get_applications(project_name=None, project_id=None):
    project = get_project(name=project_name, project_id=project_id)
    if project:
        resp = _api_get(project['url'] + '/applications')
        if resp.status_code == requests.codes.ok:
            return resp.json()
    return []


def _name_and_or_id(name, a_id):
    name_id = []
    if name:
        name_id.append('name: {}'.format(name))
    if a_id:
        name_id.append('id: {}'.format(a_id))
    return ', '.join(name_id)


def get_application(app_name=None, app_id=None, project_name=None, project_id=None):
    apps = get_applications(project_name=project_name, project_id=project_id)
    app = [a for a in apps if (app_name is None or app_name == a['name']) and (app_id is None or app_id == a['id'])]
    if not app:
        raise RuntimeError('Application [{}] not found in project [{}]'.format(
            _name_and_or_id(app_name, app_id),
            _name_and_or_id(project_name, project_id)))
    return app[0]
