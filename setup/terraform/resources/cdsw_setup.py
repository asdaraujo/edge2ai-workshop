#!/usr/bin/env python

import requests
import sys
import time

PUBLIC_IP = sys.argv[1]
MODEL_PKL_FILE = sys.argv[2]
CDSW_API = 'http://cdsw.%s.nip.io/api/v1' % (PUBLIC_IP,)
CDSW_ALTUS_API = 'http://cdsw.%s.nip.io/api/altus-ds-1' % (PUBLIC_IP,)

USERNAME = 'admin'
PASSWORD = 'supersecret1'
FULL_NAME = 'Workshop Admin'
EMAIL = 'admin@cloudera.com'

print('# Prepare CDSW for workshop')
r = None
try:
    s = requests.Session()
    
    print('# Create user')
    while True:
        try:
            r = s.post(CDSW_API + '/users', json={
                    'email': EMAIL,
                    'name': FULL_NAME,
                    'username': USERNAME,
                    'password': PASSWORD,
                    'type': 'user'
                }, timeout=10)
            if r.status_code == 201:
                break
            elif r.status_code == 422:
                print('WARNING: User admin already exists')
                break
        except requests.exceptions.ConnectTimeout:
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
    r = s.post(CDSW_ALTUS_API + '/models/list-models', json={'projectOwnerName': 'admin', 'latestModelDeployment': True, 'latestModelBuild': True})
    models = [m for m in r.json() if m['name'] == 'IoT Prediction Model']
    if models and models[0]['latestModelDeployment']['status'] == 'deployed':
        print('Model is already deployed!! Skipping.')
        exit(0)

    print('# Add engine')
    r = s.post(CDSW_API + '/site/engine-profiles', json={'cpu': 1, 'memory': 4})
    engine_id = r.json()['id']
    print('Engine ID: %s'% (engine_id,))
    
    print('# Add environment variable')
    r = s.patch(CDSW_API + '/site/config', json={'environment': '{"HADOOP_CONF_DIR":"/etc/hadoop/conf/"}'})
    
    print('# Add project')
    r = s.post(CDSW_API + '/users/admin/projects', json={'template': 'git',
                                                         'project_visibility': 'private',
                                                         'name': 'Edge2AI Workshop',
                                                         'gitUrl': 'https://github.com/asdaraujo/edge2ai-workshop'})
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
            'name': 'IoT Prediction Model',
            'description': 'IoT Prediction Model',
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
    
    while True:
        r = s.post(CDSW_ALTUS_API + '/models/list-models', json={
            'project': str(project_id),
            'latestModelDeployment': True,
            'latestModelBuild': True,
        })
        models = [m for m in r.json() if m['id'] == str(model_id)]
        if models:
            build_status = models[0]['latestModelBuild']['status']
            deployment_status = models[0]['latestModelDeployment']['status']
            print('Model %s: build status: %s, deployment status: %s' % (model_id, build_status, deployment_status))
            if build_status == 'built' and deployment_status == 'deployed':
                break
            elif build_status == 'failed' or deployment_status == 'failed':
                raise RuntimeError('Model deployment failed')
        time.sleep(10)
except Exception as e:
    if r:
        print(r.text)
    raise
