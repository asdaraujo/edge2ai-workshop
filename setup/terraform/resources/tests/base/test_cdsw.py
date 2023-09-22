#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing CDSW
"""
import pytest
import requests
from ...labs import exception_context
from ...labs.utils import cdsw

CDSW_PROJECT_NAME = 'Edge2AI Workshop'
CDSW_MODEL_NAME = 'IoT Prediction Model'
VIZ_PROJECT_NAME = 'VizApps Workshop'
MODEL_API_REQUEST = {'feature': '0, 65, 0, 137, 21.95, 83, 19.42, 111, 9.4, 6, 3.43, 4'}
MODEL_API_RESPONSE = {'result': 1}


@pytest.mark.skipif(not cdsw.is_cdsw_installed(), reason='CDSW is not installed')
def test_cdsw_model_existence():
    model = cdsw.get_model()
    with exception_context(model):
        assert int(model.get('id', 0)) > 0
        assert model.get('name', '') == CDSW_MODEL_NAME
        assert model.get('defaultResources', {}).get('cpuMillicores', 0) == 1000
        assert model.get('defaultResources', {}).get('memoryMb', 0) == 4096
        assert model.get('latestModelBuild', {}).get('status', '') == 'built'
        assert model.get('latestModelBuild', {}).get('targetFilePath', '') == 'cdsw.iot_model.py'
        assert model.get('latestModelBuild', {}).get('targetFunctionName', '') == 'predict'
        assert model.get('latestModelDeployment', {}).get('status', '') == 'deployed'
        assert model.get('latestModelDeployment', {}).get('replicationPolicy', {}).get('numReplicas', -1) == \
               model.get('latestModelDeployment', {}).get('replicationStatus', {}).get('numReplicasAvailable', -2)
        assert model.get('project', {}).get('id', -1) == cdsw.get_project().get('id', -2)


@pytest.mark.skipif(not cdsw.is_cdsw_installed(), reason='CDSW is not installed')
def test_cdsw_project_existence():
    project = cdsw.get_project()
    with exception_context(project):
        assert project.get('id', 0) > 0


@pytest.mark.skipif(not cdsw.is_cdsw_installed(), reason='CDSW is not installed')
def test_cdsw_api_key_operations():
    num_keys_before = len(cdsw.get_model_api_keys())
    api_key = cdsw.create_model_api_key(return_object=True)
    num_keys_after = len(cdsw.get_model_api_keys())
    with exception_context(api_key):
        legacy_api_key = 'modelapikey' in api_key
        if legacy_api_key:
            assert api_key['modelapikey']
        else:
            assert api_key.get('apiKey', None)
        assert num_keys_after == num_keys_before + 1
        cdsw.delete_model_api_key(api_key['keyid'])
        num_keys_after_delete = len(cdsw.get_model_api_keys())
        assert num_keys_after_delete == num_keys_before


@pytest.mark.skipif(not cdsw.is_cdsw_installed(), reason='CDSW is not installed')
def test_cdsw_model_api():
    model = cdsw.get_model()
    with exception_context(model):
        access_key = model.get('accessKey', None)
        assert access_key is not None
        resp = requests.post(
            cdsw.get_model_endpoint_url(),
            json={
                'accessKey': access_key,
                'request': MODEL_API_REQUEST,
            },
            headers={
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + cdsw.create_model_api_key(),
            },
            verify=cdsw.get_session().verify,
        )
        assert resp.status_code == requests.codes.ok
        response = resp.json()
        assert response['success'] is True
        assert response['response'] == MODEL_API_RESPONSE
