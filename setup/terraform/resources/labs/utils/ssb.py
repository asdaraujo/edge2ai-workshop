#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import uuid

from . import *

_SSB_USER = 'admin'
_SSB_SESSION = None
_SSB_CSRF_TOKEN = None

_API_INTERNAL = 'internal'
_API_EXTERNAL = 'external'
_API_UI = 'ui'


def _get_api_url():
    return get_url_scheme() + '://cdp.{}.nip.io:8000/api/v1'.format(get_public_ip())


def _get_rest_api_url():
    return get_url_scheme() + '://cdp.{}.nip.io:18121/api/v1'.format(get_public_ip())


def _get_ui_url():
    return get_url_scheme() + '://cdp.{}.nip.io:8000/ui'.format(get_public_ip())


def _get_url(api_type):
    if api_type == _API_UI:
        return _get_ui_url()
    elif api_type == _API_INTERNAL:
        return _get_api_url()
    else:
        return _get_rest_api_url()


def _api_call(func, path, data=None, files=None, headers=None, api_type=_API_INTERNAL, token=False):
    global _SSB_CSRF_TOKEN
    if not headers:
        headers = {}
    if api_type != _API_UI:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data)
    if api_type == _API_EXTERNAL:
        headers['Username'] = 'admin'
    if token:
        headers['X-CSRF-TOKEN'] = _SSB_CSRF_TOKEN
    url = _get_url(api_type) + path
    resp = func(url, data=data, headers=headers, files=files)
    if resp.status_code != requests.codes.ok:
        raise RuntimeError("Call to {} returned status {}. \nData: {}\nResponse: {}".format(
            url, resp.status_code, json.dumps(data), resp.text))

    m = re.match(r'.*name="csrf_token" type="hidden" value="([^"]*)"', resp.text, flags=re.DOTALL)
    if m:
        _SSB_CSRF_TOKEN = m.groups()[0]

    return resp


def _api_get(path, data=None, api_type=_API_INTERNAL, token=False):
    return _api_call(_get_session().get, path, data=data, api_type=api_type, token=token)


def _api_post(path, data=None, files=None, headers=None, api_type=_API_INTERNAL, token=False):
    return _api_call(_get_session().post, path, data=data, files=files, headers=headers, api_type=api_type, token=token)


def _api_delete(path, data=None, api_type=_API_INTERNAL, token=False):
    return _api_call(_get_session().delete, path, data=data, api_type=api_type, token=token)


def _get_session():
    global _SSB_SESSION
    if not _SSB_SESSION:
        _SSB_SESSION = requests.Session()
        if is_tls_enabled():
            _SSB_SESSION.verify = get_truststore_path()

        _api_get('/login', api_type=_API_UI)
        _api_post('/login', {'next': '', 'login': _SSB_USER, 'password': get_the_pwd()}, api_type=_API_UI, token=True)
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


def execute_sql(stmt, job_name=None, parallelism=None, sample_interval_millis=None, savepoint_path=None,
                start_with_savepoint=None):
    if not job_name:
        job_name = 'job_{}_{}'.format(uuid.uuid1().hex[0:4], int(1000000*time.time()))
    data = {
        'sql': stmt,
        'job_parameters': {
            'job_name': job_name,
            # 'snapshot_config': {
            #     'name': 'string',
            #     'key_column_name': 'string',
            #     'api_key': 'string',
            #     'recreate': true,
            #     'ignore_nulls': true,
            #     'enabled': true
            # },
            'parallelism': parallelism,
            'sample_interval_millis': sample_interval_millis,
            'savepoint_path': savepoint_path,
            'start_with_savepoint': start_with_savepoint
        },
        'execute_in_session': True
    }
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }
    return _api_post('/ssb/sql/execute', data, headers=headers, api_type=_API_EXTERNAL)


def get_jobs(state='RUNNING'):
    resp = _api_get('/ssb/jobs', api_type=_API_EXTERNAL)
    return [j for j in resp.json()['jobs'] if state is None or j['state'] == state]


def stop_job(job_name, savepoint=False, savepoint_path=None, timeout=1000, wait_secs=0):
    data = {
        'savepoint': savepoint,
        'savepoint_path': savepoint_path,
        'timeout': timeout,
    }
    resp = _api_post('/ssb/jobs/{}/stop'.format(job_name), api_type=_API_EXTERNAL, data=data)
    while True:
        jobs = get_jobs()
        if not any(j['name'] == job_name for j in jobs):
            break
        time.sleep(1)

    # additional wait in case we need to ensure the release of resources, like replication slots
    time.sleep(wait_secs)

    return resp


def stop_all_jobs():
    for job in get_jobs():
        stop_job(job['name'])
