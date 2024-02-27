#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import io
import json
import math
import os
import re
import requests
import sys
import time
import traceback
from base64 import b64encode
from datetime import datetime
from optparse import OptionParser
from subprocess import Popen, PIPE

from labs import get_base_dir, get_the_pwd, get_truststore_path, get_url_scheme, is_tls_enabled
from labs.utils import cm

IP_LOOKUP_URLS = [
    'http://ifconfig.me',
    'http://api.ipify.org',
    'https://ipinfo.io/ip',
]

CSRF_REGEXPS = [
    r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"',
    r'.*"csrfmiddlewaretoken": "([^"]*)"',
    r'.*\.csrf_token\("([^"]*)"\)',
    r'.*csrfToken:\s*"([^"]*)',
]

PROJECT_ZIP_FILE = os.environ.get('PROJECT_ZIP_FILE', None)

DEFAULT_USERNAME = 'admin'
DEFAULT_FIRST_NAME = 'Workshop'
DEFAULT_LAST_NAME = 'Admin'
DEFAULT_EMAIL = f'{DEFAULT_USERNAME}@cloudera.com'
DEFAULT_PROJECT_NAME = 'Edge2AI Workshop'
DEFAULT_PROJECT_GITHUB_URL = 'https://github.com/cloudera-labs/edge2ai-workshop'
DEFAULT_MODEL_NAME = 'IoT Prediction Model'
DEFAULT_UPLOAD_CHUNK_SIZE = 1048576

DEFAULT_VIZ_ADMIN_USER = 'vizapps_admin'
DEFAULT_VIZ_ADMIN_PASSWORD = 'vizapps_admin'
DEFAULT_VIZ_PROJECT_NAME = 'VizApps Workshop'
DEFAULT_VIZ_APPLICATION_NAME = 'Viz Server Application'
DEFAULT_VIZ_APPLICATION_SUBDOMAIN = 'viz'

DEFAULT_RUNTIME = {'editor': 'Workbench', 'kernel': 'Python 3.7', 'edition': 'Standard'}
DEFAULT_VIZ_RUNTIME = {'editor': 'Workbench', 'kernel': 'Cloudera Data Visualization'}


class VizAppsInvalidLoginAttempt(RuntimeError):
    def __init__(self, username):
        self.username = username
        super().__init__(f'Authentication failed for VizApps user {self.username}.')


class VizAppsUserAlreadyExists(RuntimeError):
    def __init__(self, username):
        self.username = username
        super().__init__(f'VizApps user {self.username} already exists.')


class CdswUnexpectedResponse(RuntimeError):
    def __init__(self, response, msg=None, expected_codes=None):
        self.response = response
        self.expected_codes = expected_codes
        if msg is None:
            msg = f'The {self.response.request.method} request to {self.response.url} returned an unexpected status code: {self.response.status_code}'
            if expected_codes:
                msg = f'{msg} Expected codes: {", ".join([str(e) for e in expected_codes])}.'
            msg = f'{msg} Response content: {self.response.text}'
        super().__init__(msg)

    @property
    def status_code(self):
        return self.response.status_code


class CdswEntityNotFound(RuntimeError):
    USER = 'User'
    MODEL = 'Model'
    PROJECT = 'Project'
    ENGINE_PROFILE = 'EngineProfile'
    RUNTIME = 'Runtime'
    IMAGE = 'Image'
    APPLICATION = 'Application'
    VIZ_USER = 'VizApps User'

    def __init__(self, entity_type, entity_name):
        self.entity_type = entity_type
        self.entity_name = entity_name
        super().__init__(f'{self.entity_type} {self.entity_name} not found.')


def get_public_ip():
    for url in IP_LOOKUP_URLS:
        resp = requests.get(url)
        ip_address = resp.text
        if resp.status_code == requests.codes.ok and re.match(r'[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
                                                              ip_address):
            return ip_address
    return None


def _api_call(func, url, path, expected_codes=None, **kwargs):
    if not expected_codes:
        expected_codes = [requests.codes.ok]
    resp = func(f'{url}{path}', **kwargs)
    if resp.status_code not in expected_codes:
        raise CdswUnexpectedResponse(resp, expected_codes=expected_codes)
    return resp


def _exec(cmd):
    p = Popen(cmd, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = p.communicate()
    return p.returncode, stdout.decode(), stderr.decode()


def is_cdsw_model_deployed(model):
    return model and model['latestModelBuild']['status'] == 'built' \
        and model['latestModelDeployment']['status'] == 'deployed'


def is_cdsw_model_healthy(model):
    # ModelBuildStatus:
    #   Good: pending, succeeded, built, pushing, queued
    #   Bad: build failed, timedout, unknown
    # ModelDeploymentStatus:
    #   Good: deployed, deploying, pending
    #   Bad: stopping, stopped, failed
    if model \
            and model['latestModelBuild']['status'] in ['pending', 'succeeded', 'built', 'building', 'pushing',
                                                        'queued'] \
            and model['latestModelDeployment']['status'] in ['deployed', 'deploying', 'pending']:
        return True
    return False


def get_csrf_token(txt):
    token = ''
    for regexp in CSRF_REGEXPS:
        m = re.match(regexp, txt, flags=re.DOTALL)
        if m:
            token = m.groups()[0]
            break
    return token


class CdswWatcher(object):
    IGNORE_OUTPUT_PATTERN = r'(\||----|Sending detailed logs)'
    ACTIVE_INDICATION_PATTERN = r'.*Cloudera Data Science Workbench is not ready yet'
    INTERVAL_SECS = 10

    def __init__(self, public_ip, cm_username, cm_password, use_tls=False, truststore_file=None,
                 remote_execution=False, idle_timeout_secs=2400, cluster_name='OneNodeCluster', service_name='cdsw',
                 interval_secs=INTERVAL_SECS, ignore_output_pattern=IGNORE_OUTPUT_PATTERN,
                 active_indication_pattern=ACTIVE_INDICATION_PATTERN):
        self.public_ip = public_ip
        self.cm_username = cm_username
        self.cm_password = cm_password
        self.use_tls = use_tls
        self.truststore_file = truststore_file
        self.remote_execution = remote_execution
        self.idle_timeout_secs = idle_timeout_secs
        self.cluster_name = cluster_name
        self.service_name = service_name
        self.cdsw_outputs = []
        self.latest_change_timestamp = 0
        self.interval_secs = interval_secs
        self.ignore_output_pattern = ignore_output_pattern
        self.active_indication_pattern = active_indication_pattern
        self._cm_api = None
        self.cdsw_api = CdswApi(self.public_ip, use_tls=self.use_tls, truststore_file=self.truststore_file)

    @property
    def cm_api_url(self):
        return cm.get_cm_api_url(self.public_ip, cm_auth=(self.cm_username, self.cm_password))

    @property
    def cm_api(self):
        if not self._cm_api:
            self._cm_api = requests.Session()
            if self.use_tls:
                self._cm_api.verify = self.truststore_file
            token = b64encode(f'{self.cm_username}:{self.cm_password}'.encode()).decode()
            self._cm_api.headers.update({'Authorization': f'Basic {token}'})
        return self._cm_api

    def restart_cdsw(self):
        url = f'{self.cm_api_url}/clusters/{self.cluster_name}/services/{self.service_name}/commands/restart'
        resp = self.cm_api.post(url)
        if resp.status_code == requests.codes.ok:
            return resp.text
        else:
            raise RuntimeError(f'Failed to restart CDSW. Response: {resp}')

    def wait_for_cdsw(self):
        if not self.remote_execution:
            self.wait_for_cdsw_startup()
        self.wait_for_cdsw_api()

    def wait_for_cdsw_startup(self):
        while True:
            try:
                ret, stdout, _ = _exec('sudo cdsw status < /dev/null')
                output_lines = stdout.split('\n')
                ignore_pattern = self.ignore_output_pattern
                output_lines = [line for line in output_lines if not re.match(ignore_pattern, line)]
                output = '\n'.join(output_lines)
                for idx, previous_output in enumerate(self.cdsw_outputs):
                    if output == previous_output:
                        break
                else:
                    self.latest_change_timestamp = datetime.now()
                    idx = len(self.cdsw_outputs)
                    self.cdsw_outputs.append(output)
                    print(f'Output[{idx}]:\n'
                          f'===== OUTPUT BEGINS HERE =====\n{output}\n===== OUTPUT ENDS HERE =====\n')

                elapsed_time = int(datetime.now().timestamp() - self.latest_change_timestamp.timestamp())
                fmt_time = self.latest_change_timestamp.strftime('%Y-%m-%d %H:%M:%S')
                print(f'The last CDSW status change (output [{idx}]) was at {fmt_time}, {elapsed_time} seconds ago')

                if not re.match(self.active_indication_pattern, stdout, re.DOTALL):
                    break

                if elapsed_time > self.idle_timeout_secs:
                    print('Restarting CDSW')
                    try:
                        output = self.restart_cdsw()
                        print(f'Restarting is in progress:\n{output}\n')
                        self.latest_change_timestamp = datetime.now()
                    except RuntimeError as exc:
                        print('Request to restart CDSW has failed: {}'.format(exc))

            except Exception as exc:
                print(f'An unexpected exception occurred:')
                exc_type, exc_value, exc_traceback = sys.exc_info()
                traceback.print_exception(exc_type, exc_value, exc_traceback,
                                          file=sys.stdout)
            time.sleep(self.interval_secs)

        print('CDSW has successfully started!')

    def wait_for_cdsw_api(self):
        while True:
            try:
                resp = self.cdsw_api.cdsw_get('', expected_codes=[200])
                if 'Sense API v1' in resp.text:
                    break
                else:
                    status = f'API endpoint is up but response not expected: {resp.text[:30]}...'
            except requests.exceptions.ConnectTimeout as err:
                status = f'Connection timeout. Exception: {err}'
            except requests.exceptions.ConnectionError as err:
                status = f'Connection error. Exception: {err}'

            print(f'Waiting for CDSW to be ready... ({status})')

            time.sleep(self.interval_secs)

        print('CDSW API is available!')


class CdswApi(object):
    def __init__(self, public_ip=None, use_tls=False, truststore_file=None):
        self.public_ip = public_ip if public_ip else get_public_ip()
        self.use_tls = use_tls
        self.truststore_file = truststore_file
        self._api = None
        self._viz_api = None
        self.username = None
        self.password = None
        self.viz_username = None
        self.viz_password = None

    @property
    def cdsw_hostname(self):
        return f'cdsw.{self.public_ip}.nip.io'

    @property
    def cdsw_base_url(self):
        return f'{get_url_scheme()}://cdsw.{self.public_ip}.nip.io'

    @property
    def viz_base_url(self):
        return f'{get_url_scheme()}://viz.cdsw.{self.public_ip}.nip.io'

    @property
    def cdsw_api_url(self):
        return f'{self.cdsw_base_url}/api/v1'

    @property
    def altus_api_url(self):
        return f'{self.cdsw_base_url}/api/altus-ds-1'

    @property
    def viz_api_url(self):
        return f'{self.viz_base_url}/arc'

    @property
    def api(self):
        if not self._api:
            self._api = requests.Session()
            if self.use_tls:
                self._api.verify = self.truststore_file
            if self.username and self.password:
                resp = self.cdsw_post('/authenticate',
                                      json={'login': self.username, 'password': self.password}, )
                self._api.headers.update({'Authorization': 'Bearer ' + resp.json()['auth_token']})
        return self._api

    @property
    def viz_api(self):
        if not self._viz_api:
            self._viz_api = requests.Session()
            if self.use_tls:
                self._viz_api.verify = self.truststore_file
            if self.viz_username and self.viz_password:
                resp = self.viz_get('/apps/login')
                token = get_csrf_token(resp.text)
                auth_payload = (f'csrfmiddlewaretoken={token}&next=&'
                                f'username={self.viz_username}&password={self.viz_password}')
                try:
                    resp = self.viz_post('/apps/login', data=auth_payload,
                                         headers={'Content-Type': 'application/x-www-form-urlencoded'},
                                         expected_codes=[302], allow_redirects=False)
                except CdswUnexpectedResponse as exc:
                    if exc.status_code == requests.codes.ok:
                        raise VizAppsInvalidLoginAttempt(self.viz_username)
        return self._viz_api

    def set_credentials(self, username, password):
        self.username = username
        self.password = password
        self._api = None

    def set_viz_credentials(self, username, password):
        self.viz_username = username
        self.viz_password = password
        self._viz_api = None

    def cdsw_get(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.get, self.cdsw_api_url, path, expected_codes, **kwargs)

    def cdsw_post(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.post, self.cdsw_api_url, path, expected_codes, **kwargs)

    def cdsw_put(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.put, self.cdsw_api_url, path, expected_codes, **kwargs)

    def cdsw_patch(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.patch, self.cdsw_api_url, path, expected_codes, **kwargs)

    def cdsw_delete(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.delete, self.cdsw_api_url, path, expected_codes, **kwargs)

    def altus_post(self, path, expected_codes=None, **kwargs):
        return _api_call(self.api.post, self.altus_api_url, path, expected_codes, **kwargs)

    def viz_get(self, path, expected_codes=None, **kwargs):
        return _api_call(self.viz_api.get, self.viz_api_url, path, expected_codes, **kwargs)

    def viz_post(self, path, expected_codes=None, **kwargs):
        self.refresh_csrf_token_header(kwargs)
        return _api_call(self.viz_api.post, self.viz_api_url, path, expected_codes, **kwargs)

    def viz_put(self, path, expected_codes=None, **kwargs):
        self.refresh_csrf_token_header(kwargs)
        return _api_call(self.viz_api.put, self.viz_api_url, path, expected_codes, **kwargs)

    def refresh_csrf_token_header(self, kwargs):
        resp = self.viz_get('/apps/home')
        headers = kwargs.get('headers', {})
        headers.update({'X-CSRFToken': get_csrf_token(resp.text)})
        kwargs.update({'headers': headers})

    def cdsw_get_engine_profile(self, cpu, memory):
        resp = self.cdsw_get('/site/engine-profiles', expected_codes=[requests.codes.ok])
        profiles = [p for p in resp.json() if p['cpu'] == cpu and p['memory'] == memory]
        if len(profiles) == 0:
            raise CdswEntityNotFound(CdswEntityNotFound.ENGINE_PROFILE, f'CPU: {cpu}, Memmory: {memory}')
        return profiles[0]

    def cdsw_create_engine_profile(self, cpu, memory):
        profile = self.cdsw_post('/site/engine-profiles', expected_codes=[requests.codes.created],
                                 json={'cpu': cpu, 'memory': memory})
        return profile.json()

    def cdsw_ensure_engine_profile(self, cpu, memory):
        try:
            return self.cdsw_get_engine_profile(cpu, memory)
        except CdswEntityNotFound:
            return self.cdsw_create_engine_profile(cpu, memory)

    def cdsw_get_site_config(self):
        config = self.cdsw_get('/site/config', expected_codes=[requests.codes.ok])
        return config.json()

    def cdsw_patch_site_config(self, name, value):
        config = self.cdsw_patch('/site/config', expected_codes=[requests.codes.ok],
                                 json={name: value})
        return config.json()

    def cdsw_set_env_variable(self, name, value):
        env = self.cdsw_get_site_config().get('environment', None)
        config = json.loads(env) if env else {}
        config.update({name: value})
        config = self.cdsw_patch_site_config('environment', json.dumps(config))
        return config

    def cdsw_unset_env_variable(self, name):
        env = self.cdsw_get_site_config().get('environment', None)
        config = json.loads(env) if env else {}
        del config[name]
        config = self.cdsw_patch_site_config('environment', json.dumps(config))
        return config

    def cdsw_ensure_user(self, username, password, name, email):
        user = self.cdsw_post(
            '/users',
            expected_codes=[requests.codes.created, requests.codes.not_found, requests.codes.unprocessable,
                            requests.codes.unavailable],
            json={
                'email': email,
                'name': name,
                'username': username,
                'password': password,
                'type': 'user'
            })
        self.set_credentials(username, password)
        if user.status_code == requests.codes.created:
            return user.json()
        elif user.status_code == requests.codes.unprocessable:
            return self.cdsw_get_user(username)
        else:
            raise RuntimeError(f'User created failed with error code: {user.status_code}', user)

    def cdsw_get_user(self, username):
        resp = self.cdsw_get('/users')
        users = [u for u in resp.json() if u['username'] == username]
        if len(users) == 0:
            raise CdswEntityNotFound(CdswEntityNotFound.USER, username)
        assert len(users) == 1
        return users[0]

    def cdsw_get_model(self, owner, model_name):
        resp = self.altus_post('/models/list-models',
                               json={
                                   'projectOwnerName': owner,
                                   'latestModelDeployment': True,
                                   'latestModelBuild': True,
                               })
        models = [m for m in resp.json() if m['name'] == model_name]
        if len(models) == 0:
            raise CdswEntityNotFound(CdswEntityNotFound.MODEL, model_name)
        assert len(models) == 1
        return models[0]

    def cdsw_get_project(self, owner, project_name):
        resp = self.cdsw_get(f'/users/{owner}/projects')
        projects = [p for p in resp.json() if p['name'] == project_name]
        if len(projects) == 0:
            raise CdswEntityNotFound(CdswEntityNotFound.PROJECT, project_name)
        assert len(projects) == 1
        return projects[0]

    def cdsw_patch_project(self, owner, project_name, path, name, value):
        project = self.cdsw_get_project(owner, project_name)
        self.cdsw_patch(f'/projects/{project["slug"]}{path}',
                        json={name: value})
        config = self.cdsw_get(f'/projects/{project["slug"]}{path}')
        return config.json()

    def cdsw_delete_project(self, owner, project_name):
        try:
            project = self.cdsw_get_project(owner, project_name)
            self.cdsw_delete(f'/projects/{project["slug"]}', expected_codes=[requests.codes.no_content])
        except CdswEntityNotFound:
            pass

    def cdsw_create_github_project(self, owner, project_name, github_url, visibility='private'):
        project = self.cdsw_post(f'/users/{owner}/projects',
                                 expected_codes=[requests.codes.created,
                                                 requests.codes.bad_gateway],
                                 json={
                                     'template': 'git',
                                     'project_visibility': visibility,
                                     'name': project_name,
                                     'gitUrl': github_url
                                 })
        return project.json()

    def cdsw_ensure_github_project(self, owner, project_name, github_url, visibility='private'):
        try:
            return self.cdsw_get_project(owner, project_name)
        except CdswEntityNotFound:
            return self.cdsw_create_github_project(owner, project_name, github_url, visibility)

    def cdsw_create_local_project(self, owner, project_name, zipfile, visibility='private'):
        token, filename = self.cdsw_upload_file(owner, zipfile)
        project = self.cdsw_post(f'/users/{owner}/projects',
                                 expected_codes=[requests.codes.created],
                                 json={
                                     "template": "local",
                                     "name": project_name,
                                     "project_visibility": visibility,
                                     "isPrototype": False,
                                     "supportAsync": True,
                                     "avoidNameCollisions": False,
                                     "uploadToken": token,
                                     "fileName": filename,
                                     "isArchive": True
                                 })
        return project.json()

    def cdsw_ensure_local_project(self, owner, project_name, github_url, visibility='private'):
        try:
            return self.cdsw_get_project(owner, project_name)
        except CdswEntityNotFound:
            return self.cdsw_create_local_project(owner, project_name, github_url, visibility)

    def cdsw_create_blank_project(self, owner, project_name, visibility='private'):
        project = self.cdsw_post(f'/users/{owner}/projects',
                                 expected_codes=[requests.codes.created],
                                 json={
                                     "template": 'blank',
                                     "name": project_name,
                                     "project_visibility": visibility,
                                 })
        return project.json()

    def cdsw_ensure_blank_project(self, owner, project_name, visibility='private'):
        try:
            return self.cdsw_get_project(owner, project_name)
        except CdswEntityNotFound:
            return self.cdsw_create_blank_project(owner, project_name, visibility)

    def cdsw_upload_file(self, owner, zipfile, chunk_size=None):
        uniqueness_token = str(time.time())[:9]
        filename = os.path.basename(zipfile)
        total_size = os.stat(zipfile).st_size
        chunk_size = DEFAULT_UPLOAD_CHUNK_SIZE if chunk_size is None else chunk_size
        total_chunks = math.ceil(total_size / chunk_size)

        fd = open(zipfile, 'rb')
        chunk = 0
        while True:
            buf = fd.read(chunk_size)
            if not buf:
                break
            chunk += 1
            buf_size = len(buf)
            self.cdsw_post(f'/upload/{owner}',
                           expected_codes=[requests.codes.ok],
                           data={
                               'uploadType': 'archive',
                               'uploadToken': uniqueness_token,
                               'flowChunkNumber': chunk,
                               'flowChunkSize': buf_size,
                               'flowCurrentChunkSize': buf_size,
                               'flowTotalSize': total_size,
                               'flowIdentifier': uniqueness_token + '-' + filename,
                               'flowFilename': filename,
                               'flowRelativePath': filename,
                               'flowTotalChunks': total_chunks,
                           },
                           files={
                               'file': (filename, io.BytesIO(buf), 'application/zip')
                           })
        return uniqueness_token, filename

    def cdsw_upload_file_to_project(self, owner, project_name, file_name, file_content):
        project = self.cdsw_get_project(owner, project_name)
        self.cdsw_put(f'/projects/{project["slug"]}/files/{file_name}', expected_codes=[requests.codes.ok],
                      files={'name': file_content})

    def cdsw_create_job(self, owner, project_name, job_name, job_type, script, kernel, cpu, memory, runtime=None):
        user = self.cdsw_get_user(owner)
        job_params = {
            'name': job_name,
            'type': job_type,
            'script': script,
            'timezone': 'America/Los_Angeles',
            'environment': {},
            'kernel': kernel,
            'cpu': cpu,
            'memory': memory,
            'nvidia_gpu': 0,
            'notifications': [{
                'user_id': user['id'],
                'success': False,
                'failure': False,
                'timeout': False,
                'stopped': False
            }],
            'recipients': {},
            'attachments': [],
        }
        if runtime is not None:
            job_params.update({'runtime_id': runtime['id']})

        project = self.cdsw_get_project(owner, project_name)
        job = self.cdsw_post(f'/projects/{project["slug"]}/jobs',
                             expected_codes=[requests.codes.created],
                             json=job_params)
        return job.json()

    def cdsw_get_runtimes(self):
        resp = self.cdsw_get('/runtimes?includeAll=true',
                             expected_codes=[requests.codes.ok, requests.codes.not_implemented])
        if resp.status_code == requests.codes.ok:
            return resp.json()['runtimes']
        elif resp.status_code == requests.codes.not_implemented:
            raise CdswEntityNotFound(CdswEntityNotFound.RUNTIME, '<any>')

    def cdsw_find_runtime(self, editor, kernel, edition=None, short_version=None, retries=600):
        total_retries = retries
        while retries > 0:
            try:
                runtimes = self.cdsw_get_runtimes()
                selected = [runtime for runtime in runtimes
                            if runtime['editor'] == editor
                            and runtime['kernel'] == kernel
                            and (edition is None or runtime['edition'] == edition)
                            and (short_version is None or runtime['shortVersion'] == short_version)]
                selected = sorted(selected, key=lambda x: (x['edition'], x['shortVersion']))
                if selected:
                    return selected[-1]
                sys.stderr.write(f'Could not find the required runtime among the {len(runtimes)} retrieved ones.'
                                 f'Will retry (#{retries} out of {total_retries} attempts).')
            except CdswEntityNotFound:
                sys.stderr.write('List of runtimes is not yet available.')
            retries -= 1
            time.sleep(1)

        raise CdswEntityNotFound(CdswEntityNotFound.RUNTIME, (editor, kernel, edition, short_version))

    def cdsw_get_release(self):
        stats = self.cdsw_get('/site/stats', expected_codes=[requests.codes.ok])
        release_str = [c['value'] for c in stats.json() if c['key'] == 'config.release'][0]
        return [int(v) for v in release_str.split('.')]

    def cdsw_start_job(self, owner, project_name, job_id):
        project = self.cdsw_get_project(owner, project_name)
        self.cdsw_post(f'/projects/{project["slug"]}/jobs/{job_id}/start', json={})

    def cdsw_get_job(self, owner, project_name, job_id):
        project = self.cdsw_get_project(owner, project_name)
        job = self.cdsw_get(f'/projects/{project["slug"]}/jobs/{job_id}', json={})
        return job.json()

    def cdsw_get_engine_image(self, repository, tag):
        images = self.cdsw_get('/engine-images')
        images = [i for i in images.json() if i['repository'] == repository and i['tag'] == tag]
        if not images:
            raise CdswEntityNotFound(CdswEntityNotFound.IMAGE, f'{repository}:{tag}')
        return images[0]

    def cdsw_create_engine_image(self, repository, tag, description):
        image = self.cdsw_post('/engine-images',
                               json={
                                   "engineImage": {
                                       "description": description,
                                       "repository": repository,
                                       "tag": tag
                                   }
                               })
        return image.json()

    def cdsw_ensure_engine_image(self, repository, tag, description):
        try:
            return self.cdsw_get_engine_image(repository, tag)
        except CdswEntityNotFound:
            return self.cdsw_create_engine_image(repository, tag, description)

    def cdsw_get_project_engine_image(self, owner, project_name):
        project = self.cdsw_get_project(owner, project_name)
        engine_image = self.cdsw_get(f'/projects/{project["slug"]}/engine-images')
        return engine_image.json()

    def cdsw_create_model(self, owner, project_name, model_name, kernel, engine_image_id, target_file_path,
                          target_function_name, examples, cpu_millicores, memory_mb, replication_policy_type,
                          num_replicas, environment=None, visibility='private', runtime_id=None):
        job_params = {}
        if runtime_id:
            job_params = {
                'runtimeId': runtime_id,
                'authEnabled': True,
                "addons": [],
            }

        project = self.cdsw_get_project(owner, project_name)
        job_params.update({
            'projectId': project['id'],
            'name': model_name,
            'description': model_name,
            'visibility': visibility,
            'targetFilePath': target_file_path,
            'targetFunctionName': target_function_name,
            'engineImageId': engine_image_id,
            'kernel': kernel,
            'examples': examples,
            'cpuMillicores': cpu_millicores,
            'memoryMb': memory_mb,
            'replicationPolicy': {'type': replication_policy_type, 'numReplicas': num_replicas},
            'environment': {} if environment is None else environment,
        })
        model = self.altus_post('/models/create-model', json=job_params)
        return model.json()

    def cdsw_get_applications(self, owner, project_name):
        project = self.cdsw_get_project(owner, project_name)
        apps = self.cdsw_get(f'/projects/{project["slug"]}/applications',
                             expected_codes=[requests.codes.ok])
        return apps.json()

    def cdsw_restart_application(self, owner, project_name, subdomain):
        app = self.cdsw_get_application_by_subdomain(owner, project_name, subdomain)
        return self.cdsw_put(f'/projects/{app["project"]["slug"]}/applications/{app["id"]}/restart', json={})

    def cdsw_get_application_by_subdomain(self, owner, project_name, subdomain):
        app = [a for a in self.cdsw_get_applications(owner, project_name) if a['subdomain'] == subdomain]
        if not app:
            raise CdswEntityNotFound(CdswEntityNotFound.APPLICATION, f'subdomain={subdomain}')
        return app[0]

    def cdsw_create_application(self, owner, project_name, subdomain, name, description, app_type, script, bypass_auth,
                                kernel, cpu, memory, environment=None, runtime_id=None):
        params = {
            'subdomain': subdomain,
            'name': name,
            'description': description,
            'type': app_type,
            'script': script,
            'bypass_authentication': bypass_auth,
            'kernel': kernel,
            'cpu': cpu,
            'memory': memory,
            'nvidia_gpu': 0,
            'environment': environment if environment else {}
        }
        if runtime_id:
            params.update({'runtime_id': runtime_id})
        project = self.cdsw_get_project(owner, project_name)
        app = self.cdsw_post(f'/projects/{project["slug"]}/applications',
                             expected_codes=[requests.codes.created],
                             json=params)
        return app.json()

    def viz_get_user(self, username):
        resp = self.viz_get(f'/apps/users_api')
        user = [u for u in resp.json() if u['username'] == username]
        if len(user) == 0:
            raise CdswEntityNotFound(CdswEntityNotFound.VIZ_USER, username)
        return user[0]

    def viz_change_user_password(self, username, old_password, new_password):
        current_username = self.viz_username
        current_password = self.viz_password
        self.set_viz_credentials(username, old_password)
        # Set new password
        data = f'old_password={old_password}&new_password={new_password}'
        cdsw_release = self.cdsw_get_release()
        if cdsw_release >= [1, 10]:
            data = f'{data}&confirm_password={new_password}'
        self.viz_put(f'/apps/users_api/{username}', data=data,
                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
        self.set_viz_credentials(current_username, current_password)

    def viz_create_user(self, username, password, first_name, last_name):
        try:
            self.viz_get_user(username)
            raise VizAppsUserAlreadyExists(username)
        except CdswEntityNotFound:
            cdsw_release = self.cdsw_get_release()
            if cdsw_release >= [1, 10]:
                pwd = 'temp_password123'
            else:
                pwd = password

            resp = self.viz_post(f'/apps/users_api/{username}',
                                 data=(f'username={username}&first_name={first_name}&last_name={last_name}&'
                                       f'is_superuser=true&is_active=true&profile=%7B%22proxy_username%22%3A%22%22%7D&'
                                       f'groups=%5B%5D&roles=%5B%5D&password={pwd}&new_password={pwd}'),
                                 headers={'Content-Type': 'application/x-www-form-urlencoded'})
            user = resp.json()[0]
            if cdsw_release >= [1, 10]:
                self.viz_change_user_password(username, pwd, password)
            return user


class CdswDeployer(object):
    def __init__(self):
        self.options, _ = self._get_parser().parse_args()
        self.the_pwd = (self.options.password
                        if self.options.password
                        else (open(self.options.password_file, 'r').read().rstrip()
                              if self.options.password_file
                              else get_the_pwd()))
        self.use_tls = self.options.use_tls or is_tls_enabled()
        self.truststore_file = self.options.truststore_file if self.options.truststore_file else get_truststore_path()
        self.cdsw_api = CdswApi(self.options.public_ip, use_tls=self.use_tls, truststore_file=self.truststore_file)
        self.cdsw_watcher = CdswWatcher(self.options.public_ip, DEFAULT_USERNAME, self.the_pwd,
                                        use_tls=self.use_tls, truststore_file=self.truststore_file,
                                        remote_execution=self.options.remote_execution)

        self.user_id = None

    def deploy(self):
        self.print_settings()
        self.wait_for_cdsw()
        self.create_user()
        self.configure_site()
        self.deploy_model()

        cdsw_release = self.cdsw_api.cdsw_get_release()
        if cdsw_release >= [1, 7]:
            self.deploy_app()

        self.wait_for_model_to_start()

        if cdsw_release >= [1, 7]:
            self.wait_for_application_to_start()
            self.configure_vizapps()
            self.change_default_vizapps_admin_password()
            self.create_vizapps_admin_user()
        print('# CDSW setup completed successfully!')

    def print_settings(self):
        print(f'BASE_DIR:       {get_base_dir()}')
        print(f'CDSW_ALTUS_API: {self.cdsw_api.altus_api_url}')
        print(f'CDSW_API:       {self.cdsw_api.cdsw_api_url}')
        print(f'USE_TLS:        {self.use_tls}')
        print(f'MODEL_PKL_FILE: {self.options.model_pkl_file}')
        print(f'PASSWORD:       {self.the_pwd}')
        print(f'PUBLIC_IP:      {self.options.public_ip}')
        print(f'TRUSTSTORE:     {self.truststore_file}')
        print(f'VIZ_API:        {self.cdsw_api.viz_api_url}')
        print(f'-------------------------------------------------------')

    def _get_parser(self):
        opt_parser = OptionParser(usage='%prog [options]')
        opt_parser.add_option('--public-ip', action='store', dest='public_ip', help='Public IP.',
                              default=get_public_ip())
        opt_parser.add_option('--remote-execution', action='store_true', dest='remote_execution',
                              help='Execute the deployment for a remote CDSW.')
        opt_parser.add_option('--model-pkl-file', action='store', dest='model_pkl_file',
                              help='Model pickle file.')
        opt_parser.add_option('--project-zip-file', action='store', dest='project_zip_file',
                              help='Zip file with the contents of the CDSW project to create.')
        opt_parser.add_option('--password', action='store', dest='password', help='The Password.')
        opt_parser.add_option('--password-file', action='store', dest='password_file',
                              help='A file path containing The Password.')
        opt_parser.add_option('--use-tls', action='store_true', dest='use_tls',
                              help='Use TLS for all server connections.')
        opt_parser.add_option('--truststore-file', action='store', dest='truststore_file',
                              help='Path to a PEM truststore file.')
        return opt_parser

    def wait_for_cdsw(self):
        print('# Waiting for CDSW service to be available')
        self.cdsw_watcher.wait_for_cdsw()

    def configure_site(self):
        print('# Creating engine profile')
        engine = self.cdsw_api.cdsw_ensure_engine_profile(1, 4)
        engine_profile_id = engine['id']
        print(f'Engine profile ID: {engine_profile_id}')

        print('# Setting environment variables')
        self.cdsw_api.cdsw_set_env_variable('HADOOP_CONF_DIR', '/etc/hadoop/conf/')

        cdsw_release = self.cdsw_api.cdsw_get_release()
        if cdsw_release >= [1, 7]:
            print('# Allowing applications to be configured with unauthenticated access')
            config = self.cdsw_api.cdsw_patch_site_config('allow_unauthenticated_access_to_app', True)
            print(f'Set unauthenticated access flag to: {config["allow_unauthenticated_access_to_app"]}')

    def create_user(self):
        print(f'# Creating {DEFAULT_USERNAME} user')
        user = self.cdsw_api.cdsw_ensure_user(username=DEFAULT_USERNAME, password=self.the_pwd,
                                              name=f'{DEFAULT_FIRST_NAME} {DEFAULT_LAST_NAME}', email=DEFAULT_EMAIL)
        self.user_id = user['id']
        print(f'User ID: {self.user_id}')

    def deploy_model(self):
        print('# Checking if there\'s a model already running')
        try:
            model = self.cdsw_api.cdsw_get_model(DEFAULT_USERNAME, DEFAULT_MODEL_NAME)
            if is_cdsw_model_deployed(model):
                print('Model is already deployed!! Skipping.')
                return
            elif is_cdsw_model_healthy(model):
                print('Model is already being deployed!! Skipping.')
                return
            build_status = model['latestModelBuild']['status']
            deployment_status = model['latestModelDeployment']['status']
            print(f'Model ID {model["id"]} is unhealthy. Build status: {build_status}.'
                  f'Deployment status: {deployment_status}')
            print(f'# Deleting project {DEFAULT_PROJECT_NAME} due to unhealthy model deployment.')
            self.cdsw_api.cdsw_delete_project(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME)
        except CdswEntityNotFound:
            pass

        print('# Creating project')
        if self.options.project_zip_file:
            print('Creating a Local project using file {}'.format(self.options.project_zip_file))
            project = self.cdsw_api.cdsw_ensure_local_project(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME,
                                                              self.options.project_zip_file)
        else:
            print('Creating a GitHub project')
            project = self.cdsw_api.cdsw_ensure_github_project(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME,
                                                               DEFAULT_PROJECT_GITHUB_URL)
        print(f'Project ID: {project["id"]}')

        print('# Uploading setup script')
        setup_script_name = 'setup_workshop.py'
        setup_script_content = """!pip3 install --upgrade pip scikit-learn
!HADOOP_USER_NAME=hdfs hdfs dfs -mkdir /user/$HADOOP_USER_NAME
!HADOOP_USER_NAME=hdfs hdfs dfs -chown $HADOOP_USER_NAME:$HADOOP_USER_NAME /user/$HADOOP_USER_NAME
!hdfs dfs -put data/historical_iot.txt /user/$HADOOP_USER_NAME
!hdfs dfs -ls -R /user/$HADOOP_USER_NAME
"""
        self.cdsw_api.cdsw_upload_file_to_project(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME,
                                                  file_name=setup_script_name, file_content=setup_script_content)

        print('# Uploading model')
        model_pkl = open(self.options.model_pkl_file, 'rb')
        self.cdsw_api.cdsw_upload_file_to_project(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME,
                                                  file_name='iot_model.pkl', file_content=model_pkl)

        print('# Retrieving CDSW release')
        cdsw_release = self.cdsw_api.cdsw_get_release()
        print(f'CDSW release: {cdsw_release}')

        runtime = None
        if cdsw_release >= [1, 10]:
            print('# Retrieving default runtime')
            runtime = self.cdsw_api.cdsw_find_runtime(**DEFAULT_RUNTIME)
            print(f'Runtime ID: {runtime["id"]}')

        print('# Creating job to run the setup script')
        job = self.cdsw_api.cdsw_create_job(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME, 'Setup workshop',
                                            'manual', setup_script_name, 'python3', 1, 4,
                                            runtime=runtime)
        print(f'Job ID: {job["id"]}')

        print('# Running job until it succeeds')
        status = None
        while status != 'succeeded':
            self.cdsw_api.cdsw_start_job(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME, job['id'])
            while True:
                job = self.cdsw_api.cdsw_get_job(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME, job['id'])
                status = job['latest']['status']
                print(f'Job {job["id"]} status: {status}')
                if status == 'succeeded':
                    break
                if status == 'failed':
                    print('Job failed. Will retry in 5 seconds.')
                    time.sleep(5)
                    break
                time.sleep(10)

        print('# Getting engine image to use for model')
        engine_image = self.cdsw_api.cdsw_get_project_engine_image(DEFAULT_USERNAME, DEFAULT_PROJECT_NAME)
        print(f'Engine image ID: {engine_image["id"]}')

        print('# Deploying model')
        model = self.cdsw_api.cdsw_create_model(
            owner=DEFAULT_USERNAME, project_name=DEFAULT_PROJECT_NAME, model_name=DEFAULT_MODEL_NAME,
            kernel='python3', engine_image_id=engine_image['id'], target_file_path='cdsw.iot_model.py',
            target_function_name='predict',
            examples=[{'request': {'feature': '0, 65, 0, 137, 21.95, 83, 19.42, 111, 9.4, 6, 3.43, 4'}}],
            cpu_millicores=1000, memory_mb=4096, replication_policy_type='fixed', num_replicas=1,
            runtime_id=runtime['id'] if runtime else None)
        print(f'Model ID: {model["id"]}')

    def deploy_app(self):
        print('# Checking if there\'s a Viz application already running')
        try:
            app = self.cdsw_api.cdsw_get_application_by_subdomain(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME,
                                                                  DEFAULT_VIZ_APPLICATION_SUBDOMAIN)
            if app['status'] == 'running':
                print('Viz application is already running! Skipping.')
                return
            elif app['status'] == 'starting':
                print('Viz application is already starting! Skipping.')
                return
            print(f'Viz application {app["id"]} is unhealthy.')
            print(f'# Deleting project {DEFAULT_VIZ_PROJECT_NAME} due to unhealthy model deployment.')
            self.cdsw_api.cdsw_delete_project(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME)
        except CdswEntityNotFound:
            pass

        print('# Creating project for Data Visualization server')
        viz_project = self.cdsw_api.cdsw_ensure_blank_project(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME)
        print(f'Viz project ID: {viz_project["id"]}')
        print(f'Viz project URL: {viz_project["url"]}')

        cdsw_release = self.cdsw_api.cdsw_get_release()

        if cdsw_release < [1, 10]:
            print('# Creating custom engine for Data Visualization server')
            engine_image = self.cdsw_api.cdsw_ensure_engine_image(
                'docker.repository.cloudera.com/cloudera/cdv/cdswdataviz',
                '6.2.3-b18', 'dataviz-623')
            print(f'Engine Image ID: {engine_image["id"]}')

            print('# Set new engine image as default for the viz project')
            project_engine_image = self.cdsw_api.cdsw_patch_project(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME,
                                                                    '/engine-images', 'engineImageId',
                                                                    engine_image["id"])
            print(f'Project image default engine Image ID set to: {project_engine_image["id"]}')

        print('# Creating Data Visualization application')
        viz_runtime = None if cdsw_release < [1, 10] else self.cdsw_api.cdsw_find_runtime(**DEFAULT_VIZ_RUNTIME)
        app = self.cdsw_api.cdsw_create_application(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME,
                                                    subdomain=DEFAULT_VIZ_APPLICATION_SUBDOMAIN,
                                                    name=DEFAULT_VIZ_APPLICATION_NAME,
                                                    description=DEFAULT_VIZ_APPLICATION_NAME,
                                                    script='/opt/vizapps/tools/arcviz/startup_app.py',
                                                    app_type='manual', bypass_auth=True, kernel='python3', cpu=1,
                                                    memory=2,
                                                    environment={'USE_MULTIPROC': 'false'},
                                                    runtime_id=viz_runtime['id'] if viz_runtime else None)
        print(f'Application ID: {app["id"]}')

    def wait_for_model_to_start(self):
        print('# Wait for model to start')
        start_time = time.time()
        while True:
            model = self.cdsw_api.cdsw_get_model(DEFAULT_USERNAME, DEFAULT_MODEL_NAME)
            build_status = model['latestModelBuild']['status']
            deployment_status = model['latestModelDeployment']['status']
            print(f'Model {model["id"]}: build status: {build_status}, deployment status: {deployment_status}')
            if is_cdsw_model_deployed(model):
                break
            elif not is_cdsw_model_healthy(model):
                raise RuntimeError(f'Model deployment failed. Build status: {build_status}.'
                                   f'Deployment status: {deployment_status}')

            if time.time() - start_time > 600:
                raise RuntimeError("Model took too long to start.")
            time.sleep(10)

    def wait_for_application_to_start(self):
        print('# Wait for VizApps to start')
        retries = 5
        while True:
            app = self.cdsw_api.cdsw_get_application_by_subdomain(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME,
                                                                  DEFAULT_VIZ_APPLICATION_SUBDOMAIN)
            print(f'Data Visualization app status: {app["status"]}')
            if app['status'] == 'running':
                print('# Viz server app is running!')
                break
            elif app['status'] in ['failed', 'stopped']:
                if retries > 0:
                    print("Application {}. Trying a restart.".format(app['status']))
                    self.cdsw_api.cdsw_restart_application(DEFAULT_USERNAME, DEFAULT_VIZ_PROJECT_NAME,
                                                           DEFAULT_VIZ_APPLICATION_SUBDOMAIN)
                    retries -= 1
                else:
                    raise RuntimeError('Application deployment {}'.format(app['status']))
            time.sleep(10)

    def configure_vizapps(self):
        print('# Setting enable_remote_user_auth property to false.')
        self.cdsw_api.set_viz_credentials(DEFAULT_VIZ_ADMIN_USER, DEFAULT_VIZ_ADMIN_PASSWORD)
        resp = self.cdsw_api.viz_get('/reports/setting')
        enable_remote_user_auth = [s for s in resp.json() if s['setting_key'] == 'enable_remote_user_auth']
        if not enable_remote_user_auth:
            print('Skipping. This version of VizApps does not have the enable_remote_user_auth property.')
            return
        elif enable_remote_user_auth[0]['setting_value'] == 'false':
            print('The enable_remote_user_auth property is already set to false.')
            return

        self.cdsw_api.viz_post('/reports/setting', json={
            "settings": [
                {"setting_key": "enable_remote_user_auth", "setting_value": "false", "setting_read_admin_only": 0}
            ],
            "flippers": []
        })
        print('The enable_remote_user_auth property has been set to false.')

    def change_default_vizapps_admin_password(self):
        try:
            # Check if the password has already been set
            self.cdsw_api.set_viz_credentials(DEFAULT_VIZ_ADMIN_USER, self.the_pwd)
            self.cdsw_api.viz_get('/apps/users')
            print(f'# Password for user {DEFAULT_VIZ_ADMIN_USER} had already been changed.')
        except VizAppsInvalidLoginAttempt:
            print(f'# Changing password for user {DEFAULT_VIZ_ADMIN_USER}.')
            self.cdsw_api.viz_change_user_password(DEFAULT_VIZ_ADMIN_USER, DEFAULT_VIZ_ADMIN_PASSWORD, self.the_pwd)
            self.cdsw_api.set_viz_credentials(DEFAULT_VIZ_ADMIN_USER, self.the_pwd)

    def create_vizapps_admin_user(self):
        print('# Creating VizApps user ' + DEFAULT_USERNAME + '.')
        try:
            user = self.cdsw_api.viz_create_user(DEFAULT_USERNAME, self.the_pwd, 'Workshop', 'Admin')
            print('Created user [{}] with ID {}.'.format(DEFAULT_USERNAME, user['id']))
        except VizAppsUserAlreadyExists:
            print(f'VizApps user {DEFAULT_USERNAME} already exists. Skipping creation.')


def main(retries=10):
    while True:
        try:
            cd = CdswDeployer()
            cd.deploy()
            break
        except Exception as exc:
            print(f'Something went wrong. Exception:')
            exc_type, exc_value, exc_traceback = sys.exc_info()
            traceback.print_exception(exc_type, exc_value, exc_traceback,
                                      file=sys.stdout)
            if retries > 0:
                print(f'\n{retries} retry(ies) left. Retrying...\n')
                retries -= 1
            else:
                raise exc


if __name__ == '__main__':
    main()
