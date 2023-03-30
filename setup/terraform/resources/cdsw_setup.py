#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import io
import math
import os
import re
import requests
import sys
import time

PUBLIC_IP = sys.argv[1]
MODEL_PKL_FILE = sys.argv[2]
if len(sys.argv) > 3:
    PASSWORD = open(sys.argv[3]).read()
else:
    PASSWORD = os.environ['THE_PWD']

PROJECT_ZIP_FILE = os.environ.get('PROJECT_ZIP_FILE', None)

BASE_DIR = os.path.dirname(__file__) if os.path.dirname(__file__) else '.'
_IS_TLS_ENABLED = os.path.exists(os.path.join(BASE_DIR, '.enable-tls'))

TRUSTSTORE = '/opt/cloudera/security/x509/truststore.pem'
URL_SCHEME = 'https' if _IS_TLS_ENABLED else 'http'

CDSW_API = URL_SCHEME + '://cdsw.{}.nip.io/api/v1'.format(PUBLIC_IP, )
CDSW_ALTUS_API = URL_SCHEME + '://cdsw.{}.nip.io/api/altus-ds-1'.format(PUBLIC_IP, )
VIZ_API = URL_SCHEME + '://viz.cdsw.{}.nip.io/arc/apps'.format(PUBLIC_IP, )
VIZ_ADMIN_USER = 'vizapps_admin'

_DEFAULT_PROJECT_NAME = 'Edge2AI Workshop'
_VIZ_PROJECT_NAME = 'VizApps Workshop'

USERNAME = 'admin'
FULL_NAME = 'Workshop Admin'
EMAIL = 'admin@cloudera.com'

_MODEL_NAME = 'IoT Prediction Model'

_CDSW_SESSION = requests.Session()
_VIZ_SESSION = requests.Session()
_RELEASE = []
_RUNTIMES = {}
_DEFAULT_RUNTIME = 0
_VIZ_RUNTIME = 0
_MODEL = {}
_DEFAULT_PROJECT = {}
_VIZ_PROJECT = {}

_UPLOAD_CHUNK_SIZE = 1048576


class VizAppsInvalidLoginAttempt(RuntimeError):
    def __init__(self, msg=None):
        super().__init__(msg)


def _init_sessions():
    global _CDSW_SESSION
    global _VIZ_SESSION
    global _IS_TLS_ENABLED
    print("Initializing sessions")
    if _IS_TLS_ENABLED:
        print("Setting truststore")
        _CDSW_SESSION.verify = TRUSTSTORE
        _VIZ_SESSION.verify = TRUSTSTORE


def _authorize_sessions():
    global _CDSW_SESSION
    print("Authorizing sessions")
    resp = _cdsw_post(CDSW_API + '/authenticate',
                      json={'login': USERNAME, 'password': PASSWORD})
    token = resp.json()['auth_token']
    _CDSW_SESSION.headers.update({'Authorization': 'Bearer ' + token})


def _get_release():
    global _RELEASE
    if not _RELEASE:
        resp = _cdsw_get(CDSW_API + '/site/stats')
        release_str = [c['value'] for c in resp.json() if c['key'] == 'config.release'][0]
        _RELEASE = [int(v) for v in release_str.split('.')]
        print('CDSW release: {}'.format(_RELEASE))
    return _RELEASE


def _get_runtimes(refresh=False):
    global _RUNTIMES
    if not _RUNTIMES or refresh:
        resp = _cdsw_get(CDSW_API + '/runtimes?includeAll=true', expected_codes=[200, 501])
        if resp.status_code == 200:
            _RUNTIMES = resp.json()['runtimes']
        elif resp.status_code == 501:
            _RUNTIMES = []
            print("List of runtimes not available yet.")
    return _RUNTIMES


def _find_runtime(editor, kernel, edition=None, short_version=None, retries=600):
    total_retries = retries
    while True:
        runtimes = _get_runtimes(refresh=True)
        selected = [runtime for runtime in runtimes
                    if runtime['editor'] == editor
                    and runtime['kernel'] == kernel
                    and (edition is None or runtime['edition'] == edition)
                    and (short_version is None or runtime['shortVersion'] == short_version)]
        selected = sorted(selected, key=lambda x: (x['edition'], x['shortVersion']))
        if selected:
            return selected[-1]['id']
        retries -= 1
        if retries <= 0:
            break
        print('Could not find the required runtime among the {} retrieved ones.'
              'Will retry (#{} out of {} attempts).'.format(len(runtimes), retries, total_retries))
        time.sleep(1)
    raise RuntimeError('Could not find the required runtime. Giving up. Available runtimes: {}'.format(runtimes))


def _get_default_runtime():
    global _DEFAULT_RUNTIME
    if not _DEFAULT_RUNTIME:
        _DEFAULT_RUNTIME = _find_runtime('Workbench', 'Python 3.7', 'Standard')
        print('Default Runtime ID: {}'.format(_DEFAULT_RUNTIME, ))
    return _DEFAULT_RUNTIME


def _get_viz_runtime():
    global _VIZ_RUNTIME
    if not _VIZ_RUNTIME:
        _VIZ_RUNTIME = _find_runtime('Workbench', 'Cloudera Data Visualization')
        print('Viz Runtime ID: {}'.format(_VIZ_RUNTIME, ))
    return _VIZ_RUNTIME


def _get_model(refresh=False):
    global _MODEL_NAME
    global _MODEL
    if not _MODEL or refresh:
        resp = _cdsw_post(CDSW_ALTUS_API + '/models/list-models',
                          json={
                              'projectOwnerName': 'admin',
                              'latestModelDeployment': True,
                              'latestModelBuild': True,
                          })
        models = [m for m in resp.json() if m['name'] == _MODEL_NAME]
        if models:
            _MODEL = models[0]
        else:
            _MODEL = {}
    return _MODEL


def _is_model_deployed():
    model = _get_model(refresh=True)
    return model and model['latestModelDeployment']['status'] == 'deployed'


def _rest_call(func, url, expected_codes=None, **kwargs):
    if not expected_codes:
        expected_codes = [200]
    resp = func(url, **kwargs)
    if resp.status_code not in expected_codes:
        print(resp.text)
        raise RuntimeError("Unexpected response: {}".format(resp))
    return resp


def _cdsw_get(url, expected_codes=None, **kwargs):
    global _CDSW_SESSION
    return _rest_call(_CDSW_SESSION.get, url, expected_codes, **kwargs)


def _cdsw_post(url, expected_codes=None, **kwargs):
    global _CDSW_SESSION
    return _rest_call(_CDSW_SESSION.post, url, expected_codes, **kwargs)


def _cdsw_put(url, expected_codes=None, **kwargs):
    global _CDSW_SESSION
    return _rest_call(_CDSW_SESSION.put, url, expected_codes, **kwargs)


def _cdsw_patch(url, expected_codes=None, **kwargs):
    global _CDSW_SESSION
    return _rest_call(_CDSW_SESSION.patch, url, expected_codes, **kwargs)


def _cdsw_delete(url, expected_codes=None, **kwargs):
    global _CDSW_SESSION
    return _rest_call(_CDSW_SESSION.delete, url, expected_codes, **kwargs)


def _viz_get(url, expected_codes=None, **kwargs):
    global _VIZ_SESSION
    return _rest_call(_VIZ_SESSION.get, url, expected_codes, **kwargs)


def _viz_post(url, expected_codes=None, **kwargs):
    global _VIZ_SESSION
    return _rest_call(_VIZ_SESSION.post, url, expected_codes, **kwargs)


def _viz_put(url, expected_codes=None, **kwargs):
    global _VIZ_SESSION
    return _rest_call(_VIZ_SESSION.put, url, expected_codes, **kwargs)


def _get_project(name=None, project_id=None):
    if (not name and not project_id) or (name and project_id):
        raise RuntimeError("Must specify either name or id, but not both.")
    resp = _cdsw_get(CDSW_API + '/users/admin/projects')
    for proj in resp.json():
        if (name and proj['name'] == name) or (project_id and proj['id'] == project_id):
            return proj
    return {}


def _create_github_project():
    return _cdsw_post(CDSW_API + '/users/admin/projects', expected_codes=[201, 502],
                      json={'template': 'git',
                            'project_visibility': 'private',
                            'name': _DEFAULT_PROJECT_NAME,
                            'gitUrl': 'https://github.com/cloudera-labs/edge2ai-workshop'})


def _create_local_project(zipfile):
    token = str(time.time())[:9]
    filename = os.path.basename(zipfile)
    total_size = os.stat(zipfile).st_size
    total_chunks = math.ceil(total_size / _UPLOAD_CHUNK_SIZE)

    f = open(zipfile, 'rb')
    chunk = 0
    while True:
        buf = f.read(_UPLOAD_CHUNK_SIZE)
        if not buf:
            break
        chunk += 1
        chunk_size = len(buf)
        _cdsw_post(CDSW_API + '/upload/admin', expected_codes=[200],
                   data={
                       'uploadType': 'archive',
                       'uploadToken': token,
                       'flowChunkNumber': chunk,
                       'flowChunkSize': chunk_size,
                       'flowCurrentChunkSize': chunk_size,
                       'flowTotalSize': total_size,
                       'flowIdentifier': token + '-' + filename,
                       'flowFilename': filename,
                       'flowRelativePath': filename,
                       'flowTotalChunks': total_chunks,
                   },
                   files={'file': (filename, io.BytesIO(buf), 'application/zip')}
                   )

    return _cdsw_post(CDSW_API + '/users/admin/projects', expected_codes=[201],
                      json={
                          "name": _DEFAULT_PROJECT_NAME,
                          "project_visibility": "private",
                          "template": "local",
                          "isPrototype": False,
                          "supportAsync": True,
                          "avoidNameCollisions": False,
                          "uploadToken": token,
                          "fileName": filename,
                          "isArchive": True
                      })


def _get_default_project():
    global _DEFAULT_PROJECT
    if not _DEFAULT_PROJECT:
        _DEFAULT_PROJECT = _get_project(name=_DEFAULT_PROJECT_NAME)
    return _DEFAULT_PROJECT


def _get_viz_project():
    global _VIZ_PROJECT
    if not _VIZ_PROJECT:
        _VIZ_PROJECT = _get_project(name=_VIZ_PROJECT_NAME)
    return _VIZ_PROJECT


def start_model(build_id):
    _cdsw_post(CDSW_ALTUS_API + '/models/deploy-model', json={
        'modelBuildId': build_id,
        'cpuMillicores': 1000,
        'memoryMb': 4096,
    })


def _get_viz_user(username):
    resp = _viz_get(VIZ_API + '/users_api',
                    headers={
                        'Content-Type': 'application/json',
                        'X-CSRFToken': _get_vizapps_csrf_token(),
                    })
    for user in resp.json():
        if user['username'] == username:
            return user
    return {}


CSRF_REGEXPS = [
    r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"',
    r'.*"csrfmiddlewaretoken": "([^"]*)"',
    r'.*\.csrf_token\("([^"]*)"\)'
]


def _get_csrf_token(txt, quiet=False):
    token = None
    for regexp in CSRF_REGEXPS:
        m = re.match(regexp, txt, flags=re.DOTALL)
        if m:
            token = m.groups()[0]
            break
    else:
        if not quiet:
            raise RuntimeError("Cannot find CSRF token.")
    return token


def _get_vizapps_csrf_token(username=VIZ_ADMIN_USER, password=PASSWORD):
    resp = _viz_get(VIZ_API + '/login')
    token = _get_csrf_token(resp.text)
    resp = _viz_post(VIZ_API + '/login?',
                     data='csrfmiddlewaretoken=' + token + '&next=&username=' + username + '&password=' + password,
                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
    token = _get_csrf_token(resp.text, quiet=True)
    if token is None or 'Invalid login' in resp.text:
        raise VizAppsInvalidLoginAttempt()
    return token


def set_vizapps_pwd():
    print('# Setting vizapps_admin password.')
    try:
        token = _get_vizapps_csrf_token(VIZ_ADMIN_USER, VIZ_ADMIN_USER)
    except VizAppsInvalidLoginAttempt:
        print('vizapps_admin password has already been changed. Skipping.')
        return

    data = 'csrfmiddlewaretoken=' + token + '&old_password=' + VIZ_ADMIN_USER + '&new_password=' + PASSWORD
    if _get_release() >= [1, 10]:
        data = data + '&confirm_password=' + PASSWORD

    _viz_put(VIZ_API + '/users_api/vizapps_admin',
             data=data,
             headers={
                 'Content-Type': 'application/x-www-form-urlencoded',
                 'X-CSRFToken': token,
             })


def _add_vizapps_user(username, password, first_name, last_name):
    print('# Adding VizApps user ' + username + '.')
    if _get_viz_user(username):
        print('Viz user [{}] already exists. Skipping creation.'.format(username))
    else:
        if _get_release() >= [1, 10]:
            pwd = 'temp_password123'
        else:
            pwd = password
        token = _get_vizapps_csrf_token(VIZ_ADMIN_USER, PASSWORD)
        resp = _viz_post(VIZ_API + '/users_api/' + username,
                         data='csrfmiddlewaretoken=' + token +
                              '&username=' + username +
                              '&first_name=' + first_name +
                              '&last_name=' + last_name +
                              '&is_superuser=true' +
                              '&is_active=true' +
                              '&profile=%7B%22proxy_username%22%3A%22%22%7D' +
                              '&groups=%5B%5D' +
                              '&roles=%5B%5D' +
                              '&password=' + pwd +
                              '&new_password=' + pwd,
                         headers={
                             'Content-Type': 'application/x-www-form-urlencoded',
                             'X-CSRFToken': token,
                         })
        user = resp.json()[0]
        if _get_release() >= [1, 10]:
            token = _get_vizapps_csrf_token(username, pwd)
            resp = _viz_put(VIZ_API + '/users_api/' + username,
                            data='csrfmiddlewaretoken=' + token +
                                 '&old_password=' + pwd +
                                 '&new_password=' + password +
                                 '&confirm_password=' + password,
                            headers={
                                'Content-Type': 'application/x-www-form-urlencoded',
                                'X-CSRFToken': token,
                            })
            user = resp.json()[0]
        print('Created user [{}] with ID {}.'.format(username, user['id']))


def main():
    print('BASE_DIR:       {}'.format(BASE_DIR))
    print('CDSW_ALTUS_API: {}'.format(CDSW_ALTUS_API))
    print('CDSW_API:       {}'.format(CDSW_API))
    print('IS_TLS_ENABLED: {}'.format(_IS_TLS_ENABLED))
    print('MODEL_PKL_FILE: {}'.format(MODEL_PKL_FILE))
    print('PASSWORD:       {}'.format(PASSWORD))
    print('PUBLIC_IP:      {}'.format(PUBLIC_IP))
    print('TRUSTSTORE:     {}'.format(TRUSTSTORE))
    print('VIZ_API:        {}'.format(VIZ_API))
    print('-------------------------------------------------------')

    print('# Prepare CDSW for workshop')
    resp = None
    try:
        _init_sessions()

        print('# Create user')
        while True:
            status = ''
            try:
                resp = _cdsw_post(CDSW_API + '/users', expected_codes=[201, 404, 422, 503],
                                  json={
                                      'email': EMAIL,
                                      'name': FULL_NAME,
                                      'username': USERNAME,
                                      'password': PASSWORD,
                                      'type': 'user'
                                  },
                                  timeout=10)
                if resp.status_code == 201:
                    print('User created')
                    break
                elif resp.status_code == 422:
                    print('User admin already exists. Skipping creation.')
                    break
                else:
                    status = 'Error code: {}'.format(resp.status_code)
            except requests.exceptions.ConnectTimeout as err:
                status = 'Connection timeout. Exception: {}'.format(err)
                pass
            except requests.exceptions.ConnectionError as err:
                status = 'Connection error. Exception: {}'.format(err)
                pass
            if status:
                print('Waiting for CDSW to be ready... ({})'.format(status))
            else:
                print('Waiting for CDSW to be ready...')
            time.sleep(10)

        _authorize_sessions()

        resp = _cdsw_get(CDSW_API + '/users')
        user = [u for u in resp.json() if u['username'] == USERNAME]
        user_id = user[0]['id']
        print('User ID: {}'.format(user_id))

        print('# Check if model is already running')
        if _is_model_deployed():
            print('Model is already deployed!! Skipping.')
        else:
            print('# Add engine')
            resp = _cdsw_post(CDSW_API + '/site/engine-profiles', expected_codes=[201],
                              json={'cpu': 1, 'memory': 4})
            engine_profile_id = resp.json()['id']
            print('Engine ID: {}'.format(engine_profile_id, ))

            print('# Add environment variable')
            _cdsw_patch(CDSW_API + '/site/config',
                        json={'environment': '{"HADOOP_CONF_DIR":"/etc/hadoop/conf/"}'})

            print('# Add project')
            _cdsw_get(CDSW_API + '/users/admin/projects')
            if not _get_default_project():
                if PROJECT_ZIP_FILE:
                    print('Creating a Local project using file {}'.format(PROJECT_ZIP_FILE))
                    _create_local_project(PROJECT_ZIP_FILE)
                else:
                    print('Creating a GitHub project')
                    _create_github_project()
            print('Project ID: {}'.format(_get_default_project()['id'], ))

            print('# Upload setup script')
            setup_script = """!pip3 install --upgrade pip scikit-learn
!HADOOP_USER_NAME=hdfs hdfs dfs -mkdir /user/$HADOOP_USER_NAME
!HADOOP_USER_NAME=hdfs hdfs dfs -chown $HADOOP_USER_NAME:$HADOOP_USER_NAME /user/$HADOOP_USER_NAME
!hdfs dfs -put data/historical_iot.txt /user/$HADOOP_USER_NAME
!hdfs dfs -ls -R /user/$HADOOP_USER_NAME
"""
            _cdsw_put(CDSW_API + '/projects/admin/edge2ai-workshop/files/setup_workshop.py',
                      files={'name': setup_script})

            print('# Upload model')
            model_pkl = open(MODEL_PKL_FILE, 'rb')
            _cdsw_put(CDSW_API + '/projects/admin/edge2ai-workshop/files/iot_model.pkl',
                      files={'name': model_pkl})

            job_params = {
                'name': 'Setup workshop',
                'type': 'manual',
                'script': 'setup_workshop.py',
                'timezone': 'America/Los_Angeles',
                'environment': {},
                'kernel': 'python3',
                'cpu': 1,
                'memory': 4,
                'nvidia_gpu': 0,
                'notifications': [{
                    'user_id': user_id,
                    'success': False,
                    'failure': False,
                    'timeout': False,
                    'stopped': False
                }],
                'recipients': {},
                'attachments': [],
            }
            if _get_release() >= [1, 10]:
                job_params.update({'runtime_id': _get_default_runtime()})

            print('# Create job to run the setup script')
            resp = _cdsw_post(CDSW_API + '/projects/admin/edge2ai-workshop/jobs', expected_codes=[201],
                              json=job_params)
            job_id = resp.json()['id']
            print('Job ID: {}'.format(job_id, ))

            status = None
            while status != 'succeeded':
                print('# Start job')
                job_url = '{}/projects/admin/edge2ai-workshop/jobs/{}'.format(CDSW_API, job_id)
                start_url = '{}/start'.format(job_url, )
                _cdsw_post(start_url, json={})
                while True:
                    resp = _cdsw_get(job_url)
                    status = resp.json()['latest']['status']
                    print('Job {} status: {}'.format(job_id, status))
                    if status == 'succeeded':
                        break
                    if status == 'failed':
                        print('# Job failed. Will retry in 5 seconds.')
                        time.sleep(5)
                        break
                    time.sleep(10)

            print('# Get engine image to use for model')
            resp = _cdsw_get(CDSW_API + '/projects/admin/edge2ai-workshop/engine-images')
            engine_image_id = resp.json()['id']
            print('Engine image ID: {}'.format(engine_image_id, ))

            print('# Deploy model')
            if _get_release() >= [1, 10]:
                job_params = {
                    'runtimeId': _get_default_runtime(),
                    'authEnabled': True,
                    "addons": [],
                }
            else:
                job_params = {}
            job_params.update({
                'projectId': _get_default_project()['id'],
                'name': _MODEL_NAME,
                'description': _MODEL_NAME,
                'visibility': 'private',
                'targetFilePath': 'cdsw.iot_model.py',
                'targetFunctionName': 'predict',
                'engineImageId': engine_image_id,
                'kernel': 'python3',
                'examples': [{'request': {'feature': '0, 65, 0, 137, 21.95, 83, 19.42, 111, 9.4, 6, 3.43, 4'}}],
                'cpuMillicores': 1000,
                'memoryMb': 4096,
                'replicationPolicy': {'type': 'fixed', 'numReplicas': 1},
                'environment': {},
            })
            resp = _cdsw_post(CDSW_ALTUS_API + '/models/create-model', json=job_params)
            try:
                model_id = resp.json()['id']
            except Exception as err:
                print(resp.json())
                raise err
            print('Model ID: {}'.format(model_id, ))

        # ================================================================================

        # See https://docs.cloudera.com/cdsw/latest/analytical-apps/topics/cdsw-application-limitations.html

        if _get_release() > [1, 9]:
            print('# Allow applications to be configured with unauthenticated access')
            resp = _cdsw_patch(CDSW_API + '/site/config',
                               json={"allow_unauthenticated_access_to_app": True})
            print('Set unauthenticated access flag to: {}'.format(resp.json()["allow_unauthenticated_access_to_app"], ))

            print('# Add project for Data Visualization server')
            if not _get_viz_project():
                _cdsw_post(CDSW_API + '/users/admin/projects', expected_codes=[201],
                           json={'template': 'blank',
                                 'project_visibility': 'private',
                                 'name': _VIZ_PROJECT_NAME})
            print('Viz project ID: {}'.format(_get_viz_project()['id'], ))
            print('Viz project URL: {}'.format(_get_viz_project()['url'], ))

            if _get_release() < [1, 10]:
                print('# Add custom engine for Data Visualization server')
                params = {
                    "engineImage": {
                        "description": "dataviz-623",
                        "repository": "docker.repository.cloudera.com/cloudera/cdv/cdswdataviz",
                        "tag": "6.2.3-b18"}
                }
                resp = _cdsw_post(CDSW_API + '/engine-images', json=params)
                engine_image_id = resp.json()['id']
                print('Engine Image ID: {}'.format(engine_image_id, ))

                print('# Set new engine image as default for the viz project')
                _cdsw_patch(_get_viz_project()['url'] + '/engine-images',
                            json={'engineImageId': engine_image_id})
                resp = _cdsw_get(_get_viz_project()['url'] + '/engine-images')
                project_engine_image_id = resp.json()['id']
                print('Project image default engine Image ID set to: {}'.format(project_engine_image_id))

            print('# Create application with Data Visualization server')
            params = {
                'bypass_authentication': True,
                'cpu': 1,
                'environment': {},
                'description': 'Viz Server Application',
                'kernel': 'python3',
                'memory': 2,
                'name': 'Viz Server Application',
                'nvidia_gpu': 0,
                'script': '/opt/vizapps/tools/arcviz/startup_app.py',
                'subdomain': 'viz',
                'type': 'manual',
                'environment': {
                    'USE_MULTIPROC': 'false',
                }
            }
            if _get_release() >= [1, 10]:
                params.update({'runtime_id': _get_viz_runtime()})
            _cdsw_post(_get_viz_project()['url'] + '/applications', expected_codes=[201, 400], json=params)
            resp = _cdsw_get(_get_viz_project()['url'] + '/applications')
            print('Application ID: {}'.format(resp.json()[0]['id']))

        # ================================================================================

        print('# Wait for model to start')
        while True:
            try:
                model = _get_model(refresh=True)
            except RuntimeError as exc:
                if '401' in exc.message:
                    pass
                raise exc
            if model:
                build_status = model['latestModelBuild']['status']
                build_id = model['latestModelBuild']['id']
                deployment_status = model['latestModelDeployment']['status']
                print('Model {}: build status: {}, deployment status: {}'.format(model['id'], build_status,
                                                                                 deployment_status))
                if build_status == 'built' and deployment_status == 'deployed':
                    break
                elif build_status == 'built' and deployment_status == 'stopped':
                    # If the deployment stops for any reason, try to give it a little push
                    start_model(build_id)
                elif build_status == 'failed' or deployment_status == 'failed':
                    raise RuntimeError('Model deployment failed')
            time.sleep(10)

        if _get_release() > [1, 9]:
            print('# Wait for VizApps to start')
            while True:
                resp = _cdsw_get(_get_viz_project()['url'] + '/applications')
                app_status = resp.json()[0]['status']
                print('Data Visualization app status: {}'.format(app_status))
                if app_status == 'running':
                    print('# Viz server app is running. CDSW setup complete!')
                    set_vizapps_pwd()
                    _add_vizapps_user('admin', PASSWORD, 'Workshop', 'Admin')
                    break
                elif app_status == 'stopped':
                    # Additional error handling - if the app exists and is stopped, start it?
                    break
                elif app_status == 'failed':
                    raise RuntimeError('Application deployment failed')
                time.sleep(10)

    except Exception as err:
        if resp:
            print(resp.text)
        raise err

    print('# CDSW setup completed successfully!')


if __name__ == '__main__':
    main()
