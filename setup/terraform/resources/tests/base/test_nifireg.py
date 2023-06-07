#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing NiFi Registry
"""
import pytest
from nipyapi import versioning
from ...labs.utils import nifi, efm

nifi.set_environment()


@pytest.mark.skipif(efm.get_efm_version() >= [1, 4, 0, 0],
                    reason='Later versions of EFM don\'t integrate with NiFi Registry')
def test_nifi_registry_iot(run_id):
    print('TEST:test_nifi_registry_iot:{}'.format(run_id))
    bucket = versioning.get_registry_bucket('IoT')
    assert bucket
    flows = versioning.list_flows_in_bucket(bucket.identifier)
    assert len(flows) == 1
    flow = flows[0]
    versions = versioning.list_flow_versions(bucket.identifier, flow.identifier)
    assert len(versions) >= 2
    assert versions[0].comments == 'Second version - ' + run_id, 'Comments: ' + versions[0].comments
    assert versions[1].comments == 'First version - ' + run_id, 'Comments: ' + versions[1].comments


def test_nifi_registry_sensorflows(run_id):
    print('TEST:test_nifi_registry_sensorflows:{}'.format(run_id))
    bucket = versioning.get_registry_bucket('SensorFlows')
    assert bucket
    flows = versioning.list_flows_in_bucket(bucket.identifier)
    assert len(flows) == 1
    flow = flows[0]
    versions = versioning.list_flow_versions(bucket.identifier, flow.identifier)
    assert len(versions) == 3
    assert versions[0].comments == 'Second version - ' + run_id, 'Comments: ' + versions[0].comments
    assert versions[1].comments == 'First version - ' + run_id, 'Comments: ' + versions[1].comments
    assert versions[2].comments == 'Enabled version control - ' + run_id, 'Comments: ' + versions[2].comments
