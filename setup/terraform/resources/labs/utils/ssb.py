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

JOB_RUNNING_STATE = 'RUNNING'
JOB_STOPPED_STATE = 'STOPPED'


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


def _user_path():
    if is_csa19_or_later():
        return '/user'
    else:
        return '/internal/user/current'


def _user_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _udf_path():
    if is_csa19_or_later():
        return '/udfs'
    else:
        return '/internal/udf'


def _udf_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _job_path():
    if is_csa19_or_later():
        return '/jobs'
    else:
        return '/ssb/jobs'


def _delete_job_path():
    if is_csa19_or_later():
        return '/jobs'
    else:
        return '/internal/jobs'


def _delete_job_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _data_source_path():
    if is_csa19_or_later():
        return '/data-sources'
    elif is_csa16_or_later():
        return '/internal/external-provider'
    else:
        return '/external-providers'


def _data_source_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _data_source_id_attr():
    if is_csa19_or_later():
        return 'id'
    else:
        return 'provider_id'


def _sql_execute_path():
    if is_csa19_or_later():
        return '/sql/execute'
    else:
        return '/ssb/sql/execute'


def _tables_path():
    if is_csa19_or_later():
        return '/tables'
    elif is_csa16_or_later():
        return '/internal/data-provider'
    else:
        return '/sb-source'


def _tables_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _tables_tree_path():
    if is_csa19_or_later():
        return '/tables/tree'
    elif is_csa16_or_later():
        return '/internal/catalog/tables-tree'
    else:
        return '/sb-source'


def _tables_tree_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    else:
        return _API_INTERNAL


def _keytab_upload_path():
    if is_csa19_or_later():
        return '/user/keytab/upload'
    elif is_csa17_or_later():
        return '/internal/user/upload-keytab'
    else:
        return '/keytab/upload'


def _keytab_upload_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    elif is_csa17_or_later():
        return _API_INTERNAL
    else:
        return _API_UI


def _keytab_generate_path():
    if is_csa19_or_later():
        return '/user/keytab/generate'
    elif is_csa17_or_later():
        return '/internal/user/generate-keytab'
    else:
        raise RuntimeError('This feature is only implemented for CSA 1.7 and later.')


def _keytab_generate_endpoint():
    if is_csa19_or_later():
        return _API_EXTERNAL
    elif is_csa17_or_later():
        return _API_INTERNAL
    else:
        return _API_UI


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
            _api_get(_user_path(), auth=auth, api_type=_user_endpoint())
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


def is_csa19_or_later():
    return _get_csa_version() >= [1, 9]


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
    return _api_post(_data_source_path(), data, api_type=_data_source_endpoint(), token=True)


def get_data_providers(provider_name=None):
    resp = _api_get(_data_source_path(), api_type=_data_source_endpoint())
    if is_csa16_or_later():
        providers = resp.json()
    else:
        providers = resp.json()['data']['providers']
    return [p for p in providers if provider_name is None or p['name'] == provider_name]


def delete_data_provider(provider_name):
    assert provider_name is not None
    for provider in get_data_providers(provider_name):
        _api_delete('{}/{}'.format(_data_source_path(), provider[_data_source_id_attr()]), api_type=_data_source_endpoint(), token=True)


def delete_all_data_providers():
    for provider in get_data_providers():
        delete_data_provider(provider['name'])


def create_udf(name, description, input_types, output_type, code):
    data = {
        'name': name,
        'description': description,
        'language': 'JavaScript',
        'input_types': input_types,
        'output_type': output_type,
        'code': code,
    }
    return _api_post(_udf_path(), data, api_type=_udf_endpoint(), token=True)


def get_udfs(udf_name=None):
    resp = _api_get(_udf_path(), api_type=_udf_endpoint())
    return [f for f in resp.json() if udf_name is None or f['name'].upper() == udf_name.upper()]


def delete_udf(udf_name=None, udf_id=None):
    assert udf_name is not None or udf_id is not None
    assert udf_name is None or udf_id is None
    if udf_id is None:
        udf = get_udfs(udf_name)
        if not udf:
            return
        udf_id = udf[0]['id']
    _api_delete('{}/{}'.format(_udf_path(), udf_id), api_type=_udf_endpoint())


def delete_all_udfs():
    for udf in get_udfs():
        delete_udf(udf_id=udf['id'])


def detect_schema(provider_name, topic_name):
    provider_id = get_data_providers(provider_name)[0][_data_source_id_attr()]
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
    provider_id = get_data_providers(provider_name)[0][_data_source_id_attr()]
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
    return _api_post(_tables_path(), data, api_type=_tables_endpoint(), token=True)


def get_tables(table_name=None, org='ssb_default'):
    resp = _api_get(_tables_tree_path(), api_type=_tables_tree_endpoint())
    if is_csa16_or_later():
        data = resp.json()
        assert 'tables' in data
        if 'ssb' in data['tables'] and org in data['tables']['ssb']:
            tables = data['tables']['ssb'][org]
        else:
            tables = []
    else:
        tables = resp.json()['data']
    return [t for t in tables if table_name is None or t['table_name'] == table_name]


def delete_table(table_name):
    assert table_name is not None
    for table in get_tables(table_name):
        _api_delete('{}/{}'.format(_tables_path(), table['id']), api_type=_tables_endpoint(), token=True)


def execute_sql(stmt, job_name=None, execution_mode='SESSION', parallelism=None, sample_interval_millis=None, savepoint_path=None,
                start_with_savepoint=None):
    if not job_name:
        job_name = 'job_{}_{}'.format(uuid.uuid1().hex[0:4], int(1000000*time.time()))
    if is_csa19_or_later():
        data = {
            'sql': stmt,
            'job_config': {
                'job_name': job_name,
                'runtime_config': {
                    'execute_mode': execution_mode,
                    'parallelism': parallelism,
                    'sample_interval': sample_interval_millis,
                    'savepoint_path': savepoint_path,
                    'start_with_savepoint': start_with_savepoint
                }
            }
        }
    else:
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
            'execute_in_session': (execution_mode == 'SESSION')
        }
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }
    return _api_post(_sql_execute_path(), data, headers=headers, api_type=_API_EXTERNAL)


def get_jobs(job_id=None, job_name=None, state=None):
    resp = _api_get(_job_path(), api_type=_API_EXTERNAL)
    return [j for j in resp.json()['jobs']
            if (state is None or j['state'] == state)
            and (job_id is None or j['job_id'] == job_id)
            and (job_name is None or j['name'] == job_name)]


def _get_job(job_name=None, job_id=None, attr=None):
    assert job_name is not None or job_id is not None
    assert job_name is None or job_id is None
    if job_id is not None:
        jobs = get_jobs(job_id=job_id)
    else:
        jobs = get_jobs(job_name=job_name)
    if jobs:
        if attr:
            return jobs[0][attr]
        else:
            return jobs[0]
    return None


def stop_job(job_name=None, job_id=None, savepoint=False, savepoint_path=None, timeout=1000, wait_secs=0):
    assert job_name is not None or job_id is not None
    assert job_name is None or job_id is None
    data = {
        'savepoint': savepoint,
        'savepoint_path': savepoint_path,
        'timeout': timeout,
    }
    if is_csa19_or_later():
        job_id = job_id or _get_job(job_name=job_name, attr='job_id')
        path = '{}/{}/stop'.format(_job_path(), job_id)
    else:
        job_name = job_name or _get_job(job_id=job_id, attr='name')
        path = '{}/{}/stop'.format(_job_path(), job_name)
    resp = _api_post(path, api_type=_API_EXTERNAL, data=data)
    while True:
        jobs = get_jobs(state=JOB_RUNNING_STATE)
        if not any((j['job_id'] == job_id or j['name'] == job_id) for j in jobs):
            break
        time.sleep(1)

    # additional wait in case we need to ensure the release of resources, like replication slots
    time.sleep(wait_secs)

    return resp


def delete_job(job_name=None, job_id=None, wait_secs=0):
    assert job_name is not None or job_id is not None
    assert job_name is None or job_id is None
    stop_job(job_name=job_name, job_id=job_id, wait_secs=wait_secs)
    job_id = job_id or _get_job(job_name=job_name, attr='job_id')
    _api_delete('{}/{}'.format(_delete_job_path(), job_id), api_type=_delete_job_endpoint())


def stop_all_jobs(delete=False, wait_secs=0):
    for job in get_jobs(state=JOB_RUNNING_STATE):
        stop_job(job_id=job['job_id'], wait_secs=wait_secs)


def delete_all_jobs(delete=False, wait_secs=0):
    for job in get_jobs():
        delete_job(job_id=job['job_id'], wait_secs=wait_secs)


def upload_keytab(principal, keytab_file):
    global _SSB_CSRF_TOKEN
    if is_csa17_or_later():
        data = {
            'principal': principal,
        }
        files = {'file': (os.path.basename(keytab_file), open(keytab_file, 'rb'), 'application/octet-stream')}

        try:
            _api_post(_keytab_upload_path(), api_type=_keytab_upload_endpoint(), data=data, files=files)
        except RuntimeError as exc:
            if exc.args and 'Keytab already exists' in exc.args[0]:
                return
            raise
    else:
        data = {
            'keytab_principal': principal,
            'csrf_token': _SSB_CSRF_TOKEN,
        }
        files = {'keytab_file': (os.path.basename(keytab_file), open(keytab_file, 'rb'), 'application/octet-stream')}
        _api_post('/keytab/upload', api_type=_keytab_upload_endpoint(), data=data, files=files, token=True)


def generate_keytab(principal, password):
    data = {
        'principal': principal,
        'password': password,
    }
    try:
        _api_post(_keytab_generate_path(), api_type=_keytab_generate_endpoint(), data=data)
    except RuntimeError as exc:
        if exc.args and 'Keytab already exists' in exc.args[0]:
            return
        raise
