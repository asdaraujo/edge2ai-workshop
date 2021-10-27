#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
from . import *

_SSB_USER = 'admin'
_SSB_SESSION = None
_SSB_CSRF_TOKEN = None

def _get_api_url():
    return get_url_scheme() + '://cdp.{}.nip.io:8000/api/v1'.format(get_public_ip())


def _get_ui_url():
    return get_url_scheme() + '://cdp.{}.nip.io:8000/ui'.format(get_public_ip())


def _api_call(func, path, data=None, files=None, headers=None, ui=False, token=False):
    global _SSB_CSRF_TOKEN
    if not headers:
        headers = {}
    if not ui:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data)
    if token:
        headers['X-CSRF-TOKEN'] = _SSB_CSRF_TOKEN
    url = (_get_ui_url() if ui else _get_api_url()) + path
    resp = func(url, data=data, headers=headers, files=files)
    if resp.status_code != requests.codes.ok:
        raise RuntimeError("Call to {} returned status {}. \nData: {}\nResponse: {}".format(
            url, resp.status_code, json.dumps(data), resp.text))

    m = re.match(r'.*name="csrf_token" type="hidden" value="([^"]*)"', resp.text, flags=re.DOTALL)
    if m:
        _SSB_CSRF_TOKEN = m.groups()[0]

    return resp


def _api_get(path, data=None, ui=False, token=False):
    return _api_call(_get_session().get, path, data=data, ui=ui, token=token)


def _api_post(path, data=None, files=None, headers=None, ui=False, token=False):
    return _api_call(_get_session().post, path, data=data, files=files, headers=headers, ui=ui, token=token)


def _api_delete(path, data=None, ui=False, token=False):
    return _api_call(_get_session().delete, path, data=data, ui=ui, token=token)


def _get_session():
    global _SSB_SESSION
    if not _SSB_SESSION:
        _SSB_SESSION = requests.Session()
        if is_tls_enabled():
            _SSB_SESSION.verify = get_truststore_path()

        _api_get('/login', ui=True)
        _api_post('/login', {'next': '', 'login': _SSB_USER, 'password': get_the_pwd()}, ui=True, token=True)
    return _SSB_SESSION


def create_data_provider(provider_name, provider_type, properties):
    data = {
        'name': provider_name,
        'provider_type': provider_type,
        'properties': properties,
    }
    return _api_post('/external-providers', data)


def get_data_providers(provider_name=None):
    resp = _api_get('/external-providers')
    providers = resp.json()['data']['providers']
    return [p for p in providers if provider_name is None or p['name'] == provider_name]


def delete_data_provider(provider_name):
    assert provider_name is not None
    for provider in get_data_providers(provider_name):
        _api_delete('/external-providers/{}'.format(provider['provider_id']))


def detect_schema(provider_name, topic_name):
    provider_id = get_data_providers(provider_name)[0]['provider_id']
    return json.dumps(_api_get('/dataprovider-endpoints/kafkaSample/{}/{}'.format(provider_id, topic_name)).json()['data'], indent=2)


def create_kafka_table(table_name, table_format, provider_name, topic_name, schema=None, transform_code=None,
                       timestamp_column=None, rowtime_column=None, watermark_seconds=None,
                       kafka_properties=None):
    assert table_format in ['JSON', 'AVRO']
    assert table_format == 'JSON' or schema is not None
    provider_id = get_data_providers(provider_name)[0]['provider_id']
    if table_format == 'JSON' and schema is None:
        schema = detect_schema(provider_name, topic_name)
    data = {
        'type': 'kafka',
        'table_name': table_name,
        'transform_code': transform_code,
        'metadata': {
            'topic': topic_name,
            'format': table_format,
            'endpoint': provider_id,
            'watermark_spec': {
                'timestamp_column': timestamp_column,
                'rowtime_column': rowtime_column,
                'watermark_seconds': watermark_seconds,
            },
            'properties': kafka_properties or {},
            "schema": schema,
        }
    }
    return _api_post('/sb-source', data, token=True)


def get_tables(table_name=None):
    resp = _api_get('/sb-source')
    tables = resp.json()['data']
    return [t for t in tables if table_name is None or t['table_name'] == table_name]


def delete_table(table_name):
    assert table_name is not None
    for table in get_tables(table_name):
        _api_delete('/sb-source/{}'.format(table['id']), token=True)


def delete_api_key(apikey):
    data = {
        'apikeys_list': '["{}"]'.format(apikey),
    }
    resp = _api_delete('/apps/apikey_api', data)


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
