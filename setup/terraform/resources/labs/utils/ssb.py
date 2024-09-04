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

API_ENDPOINT_MAPPINGS = {
    'login' : {
        '1.0': {
            ('GET', 'POST'): ('/login', _API_UI),
        },
    },
    'data-sources': {
        '1.0': {
            ('GET', 'POST'): ('/external-providers', _API_INTERNAL),
            ('DELETE',): ('/external-providers/{}', _API_INTERNAL),
        },
        '1.6': {
            ('GET', 'POST'): ('/internal/external-provider', _API_INTERNAL),
            ('DELETE',): ('/internal/external-provider/{}', _API_INTERNAL),
        },
        '1.9': {
            ('GET', 'POST'): ('/data-sources', _API_EXTERNAL),
            ('DELETE',): ('/data-sources/{}', _API_EXTERNAL),
        },
    },
    'user': {
        '1.0': {
            ('GET',): ('/internal/user/current', _API_INTERNAL),
        },
        '1.9': {
            ('GET',): ('/user', _API_EXTERNAL),
        },
    },
    'detect-schema': {
        '1.0': {
            ('GET',): ('/dataprovider-endpoints/kafkaSample/{}/{}', _API_INTERNAL),
        },
        '1.6': {
            ('GET',): ('/internal/kafka/{}/schema?topic_name={}', _API_INTERNAL),
        },
    },
    'tables': {
        '1.0': {
            ('POST',): ('/sb-source', _API_INTERNAL),
            ('DELETE',): ('/sb-source/{}', _API_INTERNAL),
        },
        '1.6': {
            ('POST',): ('/internal/data-provider', _API_INTERNAL),
            ('DELETE',): ('/internal/data-provider/{}', _API_INTERNAL),
        },
        '1.9': {
            ('POST',): ('/tables', _API_EXTERNAL),
            ('DELETE',): ('/tables/{}', _API_EXTERNAL),
        },
    },
    'tables-tree': {
        '1.0': {
            ('GET',): ('/sb-source', _API_INTERNAL),
        },
        '1.6': {
            ('GET',): ('/internal/catalog/tables-tree', _API_INTERNAL),
        },
        '1.9': {
            ('GET',): ('/tables/tree', _API_EXTERNAL),
        },
    },
    'keytab-upload': {
        '1.0': {
            ('POST',): ('/keytab/upload', _API_UI),
        },
        '1.7': {
            ('POST',): ('/internal/user/upload-keytab', _API_INTERNAL),
        },
        '1.9': {
            ('POST',): ('/user/keytab/upload', _API_EXTERNAL),
        },
    },
    'keytab-generate': {
        '1.0': {},
        '1.7': {
            ('POST',): ('/internal/user/generate-keytab', _API_INTERNAL),
        },
        '1.9': {
            ('POST',): ('/user/keytab/generate', _API_EXTERNAL),
        },
    },
    'sql-execute': {
        '1.0': {
            ('POST',): ('/ssb/sql/execute', _API_EXTERNAL),
        },
        '1.9': {
            ('POST',): ('/sql/execute', _API_EXTERNAL),
        },
    },
    'jobs': {
        '1.0': {
            ('GET',): ('/ssb/jobs', _API_EXTERNAL),
            ('DELETE',): ('/internal/jobs/{}', _API_INTERNAL),
        },
        '1.9': {
            ('GET',): ('/jobs', _API_EXTERNAL),
            ('DELETE',): ('/jobs/{}', _API_EXTERNAL),
        },
    },
    'stop-job': {
        '1.0': {
            ('POST',): ('/ssb/jobs/{}/stop', _API_EXTERNAL),
        },
        '1.9': {
            ('POST',): ('/jobs/{}/stop', _API_EXTERNAL),
        },
    },
    'udfs': {
        '1.0': {
            ('GET', 'POST'): ('/internal/udf', _API_INTERNAL),
            ('DELETE',): ('/internal/udf/{}', _API_INTERNAL),
        },
        '1.9': {
            ('GET', 'POST'): ('/udfs', _API_EXTERNAL),
            ('DELETE',): ('/udfs/{}', _API_EXTERNAL),
        },
    }
}

# Global
use_ssb_load_balancer = False
use_knox = False


def _get_api_endpoint(method, name, version=None):
    global API_ENDPOINT_MAPPINGS
    version = version or _get_csa_version()
    if callable(method):
        method = method.__name__
    method = method.upper()
    if name not in API_ENDPOINT_MAPPINGS:
        raise RuntimeError(f'API endpoint "{name}" not found.')
    for ver, endpoints in sorted([(_parse_version(k), v) for k, v in API_ENDPOINT_MAPPINGS[name].items()],
                                  key=lambda t: t[0], reverse=True):
        if version >= ver:
            for methods, endpoint in endpoints.items():
                if method in methods:
                    return _get_api_base_url(endpoint[1], version) + endpoint[0], endpoint[1]
    else:
        raise RuntimeError(f'Endpoint not found for method {method} and name {name}')


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


def _get_port(api_type=_API_EXTERNAL, use_ssb_load_balancer=use_ssb_load_balancer, use_knox=use_knox, version=None):
    if is_csa17_or_later(version):
        if use_knox:
            return '9443'
        elif use_ssb_load_balancer:
            return '8470' if is_tls_enabled() else '8070'
        else:
            return '18121'
    else:
        if api_type == _API_EXTERNAL:
            return '18121'
        else:
            return '8001' if is_tls_enabled() else '8000'


def _get_path_prefix(api_type=_API_EXTERNAL, version=None):
    if api_type == _API_UI:
        return '/ui'
    elif api_type == _API_EXTERNAL or (api_type == _API_INTERNAL and not is_csa17_or_later(version)):
        return '/api/v1'
    else:
        return ''


def _get_base_url(api_type=_API_EXTERNAL, version=None):
    if use_knox:
        path = "ssb-sse-api-lb" if use_ssb_load_balancer else "ssb-sse-api"
        path = f'/gateway/cdp-proxy-api/{path}'
    else:
        path = ''
    return f'{get_url_scheme()}://{get_hostname()}:{_get_port(api_type, version=version)}{path}'


def _get_api_base_url(api_type=_API_EXTERNAL, version=None):
    return f'{_get_base_url(api_type, version=version)}{_get_path_prefix(api_type, version=version)}'


def _api_call(func, path=None, name=None, path_params=None, data=None, files=None, headers=None, api_type=_API_INTERNAL, token=False, auth=None):
    assert (path is not None and name is None) or (path is None and name is not None), "Path and name are mutually exclusive. One of them must be specified."
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

    if name:
        url, api_type = _get_api_endpoint(func, name)
    else:
        url = _get_api_base_url(api_type) + path
    if path_params:
        url = url.format(*path_params)
    LOG.debug(f'SSB Request: method: {func.__name__.upper()}, url: {url}, auth: {"yes" if auth else "no"}, headers: {headers}, '
              f'files: {files}, data: {data}.')

    resp = func(url, data=data, headers=headers, files=files, auth=auth)
    if resp.status_code != requests.codes.ok:
        raise RuntimeError("Call to {} returned status {}. \nData: {}\nResponse: {}".format(
            url, resp.status_code, json.dumps(data), resp.text))

    token = _get_csrf_token(resp.text)
    if token:
        _SSB_CSRF_TOKEN = token
    return resp


def _api_get(path=None, name=None, path_params=None, data=None, headers=None, api_type=_API_INTERNAL, token=False, auth=None):
    return _api_call(_get_session().get, path=path, name=name, path_params=path_params, data=data, headers=headers, api_type=api_type, token=token, auth=auth)


def _api_post(path=None, name=None, path_params=None, data=None, files=None, headers=None, api_type=_API_INTERNAL, token=False):
    return _api_call(_get_session().post, path=path, name=name, path_params=path_params, data=data, files=files, headers=headers, api_type=api_type, token=token)


def _api_delete(path=None, name=None, path_params=None, data=None, api_type=_API_INTERNAL, token=False):
    return _api_call(_get_session().delete, path=path, name=name, path_params=path_params, data=data, api_type=api_type, token=token)


def _data_source_id_attr():
    if is_csa19_or_later():
        return 'id'
    else:
        return 'provider_id'


def _get_session():
    global _SSB_SESSION
    if not _SSB_SESSION:
        _SSB_SESSION = requests.Session()
        if is_tls_enabled():
            _SSB_SESSION.verify = get_truststore_path()

        if is_csa17_or_later():
            if is_kerberos_enabled():
                auth = HTTPKerberosAuth(mutual_authentication=DISABLED)
            else:
                auth = (_SSB_USER, get_the_pwd())
            _api_get(name='user', auth=auth)
        else:
            _api_get(name='login')
            _api_post(name='login', data={'next': '', 'login': _SSB_USER, 'password': get_the_pwd()}, token=True)
    return _SSB_SESSION


def _get_flink_version():
    global _FLINK_VERSION
    if not _FLINK_VERSION:
        _FLINK_VERSION = cm.get_product_version('FLINK')
    return _FLINK_VERSION


def _parse_version(version):
    return [int(t) for t in version.split('.')]


def _get_csa_version():
    parcel_version = _get_flink_version()
    version_match = re.match(r'.*csad?h?-?([0-9.]*).*', parcel_version)
    return _parse_version(version_match.groups()[0])


def is_csa16_or_later(version=None):
    return (version or _get_csa_version()) >= [1, 6]


def is_csa17_or_later(version=None):
    return (version or _get_csa_version()) >= [1, 7]


def is_csa19_or_later(version=None):
    return (version or _get_csa_version()) >= [1, 9]


def is_csa110_or_later(version=None):
    return (version or _get_csa_version()) >= [1, 10]


def is_csa113_or_later(version=None):
    return (version or _get_csa_version()) >= [1, 13]


def is_ssb_installed():
    return len(cm.get_services('SQL_STREAM_BUILDER')) > 0


def create_data_provider(provider_name, provider_type, properties, custom_truststore=True):
    if is_csa16_or_later():
        provider_type_attr = 'type'
    else:
        provider_type_attr = 'provider_type'
    data = {
        'name': provider_name,
        provider_type_attr: provider_type,
        'properties': properties,
    }
    if is_csa110_or_later():
        data['custom_truststore'] = custom_truststore
    return _api_post(name='data-sources', data=data, token=True)


def get_data_providers(provider_name=None):
    resp = _api_get(name='data-sources')
    if is_csa16_or_later():
        providers = resp.json()
    else:
        providers = resp.json()['data']['providers']
    return [p for p in providers if provider_name is None or p['name'] == provider_name]


def delete_data_provider(provider_name):
    assert provider_name is not None
    for provider in get_data_providers(provider_name):
        _api_delete(name='data-sources', path_params=[provider[_data_source_id_attr()]], token=True)


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
    return _api_post(name='udfs', data=data, token=True)


def get_udfs(udf_name=None):
    resp = _api_get(name='udfs')
    return [f for f in resp.json() if udf_name is None or f['name'].upper() == udf_name.upper()]


def delete_udf(udf_name=None, udf_id=None):
    assert udf_name is not None or udf_id is not None
    assert udf_name is None or udf_id is None
    if udf_id is None:
        udf = get_udfs(udf_name)
        if not udf:
            return
        udf_id = udf[0]['id']
    _api_delete(name='udfs', path_params=[udf_id])


def delete_all_udfs():
    for udf in get_udfs():
        delete_udf(udf_id=udf['id'])


def detect_schema(provider_name, topic_name):
    provider_id = get_data_providers(provider_name)[0][_data_source_id_attr()]
    if is_csa16_or_later():
        raw_json = _api_get(name='detect-schema', path_params=[provider_id, topic_name]).text
        return json.dumps(json.loads(raw_json), indent=2)
    else:
        return json.dumps(_api_get(name='detect-schema', path_params=[provider_id, topic_name]).json()['data'], indent=2)


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
    return _api_post(name='tables', data=data, token=True)


def get_tables(table_name=None, org='ssb_default'):
    resp = _api_get(name='tables-tree')
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
        _api_delete(name='tables', path_params=[table['id']], token=True)


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
    return _api_post(name='sql-execute', data=data, headers=headers)


def get_jobs(job_id=None, job_name=None, state=None):
    resp = _api_get(name='jobs')
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
        path_params = [job_id or _get_job(job_name=job_name, attr='job_id')]
    else:
        path_params = [job_name or _get_job(job_id=job_id, attr='name')]
    resp = _api_post(name='stop-job', path_params=path_params, data=data)
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
    _api_delete(name='jobs', path_params=[job_id])


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
            _api_post(name='keytab-upload', data=data, files=files)
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
        _api_post(name='keytab-upload', data=data, files=files, token=True)


def generate_keytab(principal, password):
    data = {
        'principal': principal,
        'password': password,
    }
    try:
        _api_post(name='keytab-generate', data=data)
    except RuntimeError as exc:
        if exc.args and 'Keytab already exists' in exc.args[0]:
            return
        raise
