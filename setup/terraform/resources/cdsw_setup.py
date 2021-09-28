#!/usr/bin/env python3
# -*- coding: utf-8 -*-

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

BASE_DIR = os.path.dirname(__file__) if os.path.dirname(__file__) else '.'
IS_TLS_ENABLED = os.path.exists(os.path.join(BASE_DIR, '.enable-tls'))

TRUSTSTORE = '/opt/cloudera/security/x509/truststore.pem'
URL_SCHEME = 'https' if IS_TLS_ENABLED else 'http'

CDSW_API = URL_SCHEME + '://cdsw.%s.nip.io/api/v1' % (PUBLIC_IP,)
CDSW_ALTUS_API = URL_SCHEME + '://cdsw.%s.nip.io/api/altus-ds-1' % (PUBLIC_IP,)
VIZ_API = URL_SCHEME + '://viz.cdsw.%s.nip.io/arc/apps' % (PUBLIC_IP,)
VIZ_ADMIN_USER = 'vizapps_admin'

PROJECT_NAME = 'Edge2AI Workshop'
VIZ_PROJECT_NAME = 'VizApps Workshop'

USERNAME = 'admin'
FULL_NAME = 'Workshop Admin'
EMAIL = 'admin@cloudera.com'

def get_project(name=None, id=None):
    if (not name and not id) or (name and id):
        raise RuntimeError("Must specify either name or id, but not both.")
    r = s.get(CDSW_API + '/users/admin/projects')
    for project in r.json():
        if (name and project['name'] == name) or (id and project['id'] == id):
            return project

def start_model(build_id):
    s.post(CDSW_ALTUS_API + '/models/deploy-model', json={
        'modelBuildId': build_id,
        'cpuMillicores': 1000,
        'memoryMb': 4096,
    })

def set_vizapps_pwd():
    print('# Setting vizapps_admin password.')
    resp = s.get(VIZ_API + '/login')
    m = re.match(r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"', resp.text, flags=re.DOTALL)
    token = m.groups()[0]

    resp = s.post(VIZ_API + '/login?',
                 data='csrfmiddlewaretoken=' + token + '&next=&username=' + VIZ_ADMIN_USER + '&password=' + VIZ_ADMIN_USER,
                 headers={'Content-Type': 'application/x-www-form-urlencoded'})
    m = re.match(r'.*"csrfmiddlewaretoken": "([^"]*)"', resp.text, flags=re.DOTALL)
    if m is None:
        print('vizapps_admin password has already been reset. Skipping.')
        return
    token = m.groups()[0]

    resp = s.put(VIZ_API + '/users_api/vizapps_admin',
                 data='csrfmiddlewaretoken=' + token + '&old_password=' + VIZ_ADMIN_USER + '&new_password=' + PASSWORD,
                 headers={
                     'Content-Type': 'application/x-www-form-urlencoded',
                     'X-CSRFToken': token,
                 })

def add_vizapps_user(username, password, first_name, last_name):
    print('# Adding VizApps user ' + username + '.')
    resp = s.get(VIZ_API + '/login')
    m = re.match(r'.*name="csrfmiddlewaretoken" type="hidden" value="([^"]*)"', resp.text, flags=re.DOTALL)
    token = m.groups()[0]

    resp = s.post(VIZ_API + '/login?',
                 data='csrfmiddlewaretoken=' + token + '&next=&username=' + VIZ_ADMIN_USER + '&password=' + PASSWORD,
                 headers={'Content-Type': 'application/x-www-form-urlencoded'})
    m = re.match(r'.*"csrfmiddlewaretoken": "([^"]*)"', resp.text, flags=re.DOTALL)
    token = m.groups()[0]

    resp = s.post(VIZ_API + '/users_api/' + username,
                  data='csrfmiddlewaretoken=' + token + '&username=' + username + '&first_name=' + first_name + '&last_name=' + last_name + '&is_superuser=true&is_active=true&profile=%7B%22proxy_username%22%3A%22%22%7D&groups=%5B%5D&roles=%5B%5D&password=' + password + '&new_password=' + password,
                  headers={
                      'Content-Type': 'application/x-www-form-urlencoded',
                      'X-CSRFToken': token,
                  })


print('# Prepare CDSW for workshop')
r = None
try:
    s = requests.Session()
    if IS_TLS_ENABLED:
        s.verify = TRUSTSTORE
    
    print('# Create user')
    while True:
        try:
            print(CDSW_API)
            r = s.post(CDSW_API + '/users',
                    json={
                        'email': EMAIL,
                        'name': FULL_NAME,
                        'username': USERNAME,
                        'password': PASSWORD,
                        'type': 'user'
                    },
                    timeout=10)
            if r.status_code == 201:
                break
            elif r.status_code == 422:
                print('WARNING: User admin already exists')
                break
        except requests.exceptions.ConnectTimeout:
            pass
        except requests.exceptions.ConnectionError:
            pass
        if r:
            print('Waiting for CDSW to be ready... (error code: %s)' % (r.status_code,))
        else:
            print('Waiting for CDSW to be ready... (connection timed out)')
        time.sleep(10)
    
    print('# Authenticate')
    r = s.post(CDSW_API + '/authenticate', json={'login': USERNAME, 'password': PASSWORD})
    s.headers.update({'Authorization': 'Bearer ' + r.json()['auth_token']})
    
    print('# Check if model is already running')
    model_name = 'IoT Prediction Model'
    r = s.post(CDSW_ALTUS_API + '/models/list-models', json={'projectOwnerName': 'admin', 'latestModelDeployment': True, 'latestModelBuild': True})
    models = [m for m in r.json() if m['name'] == model_name]
    if models and models[0]['latestModelDeployment']['status'] == 'deployed':
        model_id = models[0]['id']
        project_id = get_project(name=PROJECT_NAME)['id']
        print('Model is already deployed!! Skipping.')
    else:
        print('# Add engine')
        r = s.post(CDSW_API + '/site/engine-profiles', json={'cpu': 1, 'memory': 4})
        engine_id = r.json()['id']
        print('Engine ID: %s'% (engine_id,))

        print('# Add environment variable')
        r = s.patch(CDSW_API + '/site/config', json={'environment': '{"HADOOP_CONF_DIR":"/etc/hadoop/conf/"}'})

        print('# Add project')
        r = s.get(CDSW_API + '/users/admin/projects')
        project = get_project(name=PROJECT_NAME)
        if not project:
            r = s.post(CDSW_API + '/users/admin/projects', json={'template': 'git',
                                                                 'project_visibility': 'private',
                                                                 'name': PROJECT_NAME,
                                                                 'gitUrl': 'https://github.com/cloudera-labs/edge2ai-workshop'})
            project_id = r.json()['id']
        print('Project ID: %s'% (project_id,))

        print('# Upload setup script')
        setup_script = """!pip3 install --upgrade pip scikit-learn
!HADOOP_USER_NAME=hdfs hdfs dfs -mkdir /user/$HADOOP_USER_NAME
!HADOOP_USER_NAME=hdfs hdfs dfs -chown $HADOOP_USER_NAME:$HADOOP_USER_NAME /user/$HADOOP_USER_NAME
!hdfs dfs -put data/historical_iot.txt /user/$HADOOP_USER_NAME
!hdfs dfs -ls -R /user/$HADOOP_USER_NAME
"""
        r = s.put(CDSW_API + '/projects/admin/edge2ai-workshop/files/setup_workshop.py', files={'name': setup_script})

        print('# Upload model')
        model_pkl = open(MODEL_PKL_FILE, 'r')
        r = s.put(CDSW_API + '/projects/admin/edge2ai-workshop/files/iot_model.pkl', files={'name': model_pkl})

        print('# Create job to run the setup script')
        r = s.post(CDSW_API + '/projects/admin/edge2ai-workshop/jobs', json={
                'name': 'Setup workshop',
                'type': 'manual',
                'script': 'setup_workshop.py',
                'timezone': 'America/Los_Angeles',
                'environment':{},
                'kernel': 'python3',
                'cpu': 1,
                'memory': 4,
                'nvidia_gpu': 0,
                'notifications': [{
                    'user_id': 1,
                    'success': False,
                    'failure': False,
                    'timeout': False,
                    'stopped': False
                }],
                'recipients': {},
                'attachments': [],
            })
        job_id = r.json()['id']
        print('Job ID: %s' % (job_id,))

        print('# Start job')
        job_url = '%s/projects/admin/edge2ai-workshop/jobs/%s' % (CDSW_API, job_id)
        start_url = '%s/start' % (job_url,)

        r = s.post(start_url, json={})

        while True:
            r = s.get(job_url)
            status = r.json()['latest']['status']
            print('Job %s status: %s' % (job_id, status))
            if status == 'succeeded':
                break
            elif status == 'failed':
                raise RuntimeError('Job failed')
            time.sleep(10)

        print('# Get engine image to use for model')
        r = s.get(CDSW_API + '/projects/admin/edge2ai-workshop/engine-images')
        engine_image_id = r.json()['id']
        print('Engine image ID: %s' % (engine_image_id,))

        print('# Deploy model')
        r = s.post(CDSW_ALTUS_API + '/models/create-model', json={
                'projectId': project_id,
                'name': model_name,
                'description': model_name,
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
        model_id = r.json()['id']
        print('Model ID: %s' % (model_id,))
    
    # ================================================================================
    
    # See https://docs.cloudera.com/cdsw/latest/analytical-apps/topics/cdsw-application-limitations.html
    
    print('# Allow applications to be configured with unauthenticated access')
    r = s.patch(CDSW_API + '/site/config', json={"allow_unauthenticated_access_to_app": True})
    print('Set unauthenticated access flag to: %s'% (r.json()["allow_unauthenticated_access_to_app"],))
    
    print('# Add project for Data Visualization server')
    viz_project = None
    r = s.get(CDSW_API + '/users/admin/projects')
    for project in r.json():
        if project['name'] == VIZ_PROJECT_NAME:
            viz_project = project
            break
    if not viz_project:
        r = s.post(CDSW_API + '/users/admin/projects', json={'template': 'blank',
                                                             'project_visibility': 'private',
                                                             'name': VIZ_PROJECT_NAME})
        viz_project = r.json()
    print('Viz project ID: %s'% (viz_project['id'],))
    viz_project_url = viz_project['url']
    print('Viz project URL: %s'% (viz_project_url,))

    print('# Add custom engine for Data Visualization server')
    params = { 
      "engineImage": {
        "description": "dataviz-623",
        "repository": "docker.repository.cloudera.com/cloudera/cdv/cdswdataviz",
        "tag": "6.2.3-b18"}
    }
    r = s.post(CDSW_API + '/engine-images', json=params)
    engine_image_id = r.json()['id']
    print('Engine Image ID: %s'% (engine_image_id,))
    
    print('# Set new engine image as default for the viz project')
    print(viz_project_url + '/engine-images')
    r = s.patch(viz_project_url + '/engine-images',
                json={'engineImageId': engine_image_id})
    print(r)
    r = s.get(viz_project_url + '/engine-images')
    project_engine_image_id = r.json()['id']
    print('Project image default engine Image ID set to: %s'% (project_engine_image_id))  
      
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
        'type': 'manual'
    }
    
    r = s.post(viz_project_url + '/applications', json=params)
    r = s.get(viz_project_url + '/applications')
    r.json()
    
    
    # ================================================================================
    
    print('# Wait for model to start')
    while True:
        r = s.post(CDSW_ALTUS_API + '/models/list-models', json={
            'project': str(project_id),
            'latestModelDeployment': True,
            'latestModelBuild': True,
        })
        models = [m for m in r.json() if m['id'] == str(model_id)]
        if models:
            build_status = models[0]['latestModelBuild']['status']
            build_id = models[0]['latestModelBuild']['id']
            deployment_status = models[0]['latestModelDeployment']['status']
            print('Model %s: build status: %s, deployment status: %s' % (model_id, build_status, deployment_status))
            if build_status == 'built' and deployment_status == 'deployed':
                break
            elif build_status == 'built' and deployment_status == 'stopped':
                # If the deployment stops for any reason, try to give it a little push
                start_model(build_id)
            elif build_status == 'failed' or deployment_status == 'failed':
                raise RuntimeError('Model deployment failed')
        time.sleep(10)
    
    print('# Wait for VizApps to start')
    while True:
        r = s.get(viz_project_url + '/applications')
        app_status = r.json()[0]['status']
        print('Data Visualization app status: %s' % (app_status))
        if app_status == 'running':
          print('# Viz server app is running. CDSW setup complete!')
          set_vizapps_pwd()
          add_vizapps_user('admin', PASSWORD, 'Workshop', 'Admin')
          break
        elif app_status == 'stopped':
            # Additional error handling - if the app exists and is stopped, start it?
            break
        elif app_status == 'failed':
            raise RuntimeError('Application deployment failed')
        time.sleep(10)

except Exception as e:
    if r:
        print(r.text)
    raise
