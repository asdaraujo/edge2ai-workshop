#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import uuid

from . import *
from . import cm
from requests_kerberos import HTTPKerberosAuth, DISABLED

_SSB_USER = 'admin'
_SSB_SESSION = None
_SSB_CSRF_TOKEN = None

_API_INTERNAL = 'internal'
_API_EXTERNAL = 'external'
_API_UI = 'ui'
_FLINK_VERSION = None


_CSRF_REGEXPS = [
    r'.*name="csrf_token" type="hidden" value="([^"]*)"',
    r'.*var *csrf_token *= *"([^"]*)"'
]


def _get_csrf_token(txt, quiet=True):
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


def _get_ui_port():
    if is_csa17_or_later():
        return '18121'
    else:
        return '8001' if is_tls_enabled() else '8000'


def _get_api_url():
    if is_csa17_or_later():
        return '{}://{}:{}'.format(get_url_scheme(), get_hostname(), _get_ui_port())
    else:
        return '{}://{}:{}/api/v1'.format(get_url_scheme(), get_hostname(), _get_ui_port())


def _get_rest_api_url():
    return '{}://{}:18121/api/v1'.format(get_url_scheme(), get_hostname())


def _get_ui_url():
    return '{}://{}:{}/ui'.format(get_url_scheme(), get_hostname(), _get_ui_port())


def _get_url(api_type):
    if api_type == _API_UI:
        return _get_ui_url()
    elif api_type == _API_INTERNAL:
        return _get_api_url()
    else:
        return _get_rest_api_url()


def _api_call(func, path, data=None, files=None, headers=None, api_type=_API_INTERNAL, token=False, auth=None):
    global _SSB_CSRF_TOKEN
    if not headers:
        headers = {}
    if api_type != _API_UI and not files:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data)
    if is_kerberos_enabled():
        if not auth:
            auth = HTTPKerberosAuth(mutual_authentication=DISABLED)
    else:
        headers['Username'] = 'admin'
    if token:
        headers['X-CSRF-TOKEN'] = _SSB_CSRF_TOKEN
    url = _get_url(api_type) + path
    resp = func(url, data=data, headers=headers, files=files, auth=auth)
    if resp.status_code != requests.codes.ok:
        raise RuntimeError("Call to {} returned status {}. \nData: {}\nResponse: {}".format(
            url, resp.status_code, json.dumps(data), resp.text))

    token = _get_csrf_token(resp.text)
    if token:
        _SSB_CSRF_TOKEN = token
    return resp


def _api_get(path, data=None, headers=None, api_type=_API_INTERNAL, token=False, auth=None):
    return _api_call(_get_session().get, path, data=data, headers=headers, api_type=api_type, token=token, auth=auth)


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
        if is_csa17_or_later():
            if is_kerberos_enabled():
                auth = HTTPKerberosAuth(mutual_authentication=DISABLED)
            else:
                auth = (_SSB_USER, get_the_pwd())
            _api_get('/internal/user/current', auth=auth)
        else:
            _api_post('/login', {'next': '', 'login': _SSB_USER, 'password': get_the_pwd()}, api_type=_API_UI, token=True)
    return _SSB_SESSION


def _get_flink_version():
    global _FLINK_VERSION
    if not _FLINK_VERSION:
        _FLINK_VERSION = cm.get_product_version('FLINK')
    return _FLINK_VERSION


def _get_csa_version():
    parcel_version = _get_flink_version()
    version_match = re.match(r'.*csa-?([0-9.]*).*', parcel_version)
    return [int(v) for v in version_match.groups()[0].split('.')]


def is_csa16_or_later():
    return _get_csa_version() >= [1, 6]


def is_csa17_or_later():
    return _get_csa_version() >= [1, 7]


def is_ssb_installed():
    return len(cm.get_services('SQL_STREAM_BUILDER')) > 0


def create_data_provider(provider_name, provider_type, properties):
    if is_csa16_or_later():
        provider_type_attr = 'type'
    else:
        provider_type_attr = 'provider_type'
    data = {
        'name': provider_name,
        provider_type_attr: provider_type,
        'properties': properties,
    }
    if is_csa16_or_later():
        return _api_post('/internal/external-provider', data, api_type=_API_INTERNAL, token=True)
    else:
        return _api_post('/external-providers', data)


def get_data_providers(provider_name=None):
    if is_csa16_or_later():
        resp = _api_get('/internal/external-provider', api_type=_API_INTERNAL)
        providers = resp.json()
    else:
        resp = _api_get('/external-providers')
        providers = resp.json()['data']['providers']
    return [p for p in providers if provider_name is None or p['name'] == provider_name]


def delete_data_provider(provider_name):
    assert provider_name is not None
    for provider in get_data_providers(provider_name):
        if is_csa16_or_later():
            _api_delete('/internal/external-provider/{}'.format(provider['provider_id']), api_type=_API_INTERNAL, token=True)
        else:
            _api_delete('/external-providers/{}'.format(provider['provider_id']))


def detect_schema(provider_name, topic_name):
    provider_id = get_data_providers(provider_name)[0]['provider_id']
    if is_csa16_or_later():
        raw_json = _api_get('/internal/kafka/{}/schema?topic_name={}'.format(provider_id, topic_name)).text
        return json.dumps(json.loads(raw_json), indent=2)
    else:
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
    if is_csa16_or_later():
        return _api_post('/internal/data-provider', data, api_type=_API_INTERNAL, token=True)
    else:
        return _api_post('/sb-source', data, token=True)


def get_tables(table_name=None, org='ssb_default'):
    if is_csa16_or_later():
        data = _api_get('/internal/catalog/tables-tree').json()
        assert 'tables' in data
        if 'ssb' in data['tables'] and org in data['tables']['ssb']:
            tables = data['tables']['ssb'][org]
        else:
            tables = []
    else:
        resp = _api_get('/sb-source')
        tables = resp.json()['data']
    return [t for t in tables if table_name is None or t['table_name'] == table_name]


def delete_table(table_name):
    assert table_name is not None
    for table in get_tables(table_name):
        if is_csa16_or_later():
            _api_delete('/internal/data-provider/{}'.format(table['id']), token=True)
        else:
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


def upload_keytab(principal, keytab_file):
    global _SSB_CSRF_TOKEN
    if is_csa17_or_later():
        data = {
            'principal': principal,
        }
        files = {'file': (os.path.basename(keytab_file), open(keytab_file, 'rb'), 'application/octet-stream')}
        return _api_post('/internal/user/upload-keytab', data=data, files=files)
    else:
        data = {
            'keytab_principal': principal,
            'csrf_token': _SSB_CSRF_TOKEN,
        }
        files = {'keytab_file': (os.path.basename(keytab_file), open(keytab_file, 'rb'), 'application/octet-stream')}
        return _api_post('/keytab/upload', api_type=_API_UI, data=data, files=files, token=True)


def generate_keytab(principal, password):
    if is_csa17_or_later():
        data = {
            'principal': principal,
            'password': password,
        }
        return _api_post('/internal/user/generate-keytab', data=data)
    else:
        raise RuntimeError('This feature is only implemented for CSA 1.7 and later.')
