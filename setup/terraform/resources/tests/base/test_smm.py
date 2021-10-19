#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing SMM
"""
import pytest
import requests
from ...labs import exception_context, retry_test
from ...labs.workshop_base import CONSUMER_GROUP_ID, PRODUCER_CLIENT_ID
from ...labs.utils import smm

EXPECTED_KAFKA_CONNECT_SINK_PLUGINS = {
    "com.cloudera.dim.kafka.connect.hdfs.HdfsSinkConnector",
    "com.cloudera.dim.kafka.connect.s3.S3SinkConnector",
    "org.apache.kafka.connect.file.FileStreamSinkConnector"
}
EXPECTED_KAFKA_CONNECT_SOURCE_PLUGINS = {
    "org.apache.kafka.connect.file.FileStreamSourceConnector",
    "org.apache.kafka.connect.mirror.MirrorCheckpointConnector",
    "org.apache.kafka.connect.mirror.MirrorHeartbeatConnector",
    "org.apache.kafka.connect.mirror.MirrorSourceConnector"
}


@retry_test(max_retries=300, wait_time_secs=1)
def test_smm_topic():
    resp = smm.api_get('/api/v1/admin/metrics/aggregated/topics', params={'from': '-1', 'to': '-1'})
    topics = resp.json()
    with exception_context(topics):
        assert 'aggrTopicMetricsCollection' in topics
        metrics = [m for m in topics['aggrTopicMetricsCollection'] if m['name'] == 'iot']
        assert metrics
        assert metrics[0]['bytesInCount'] > 0
        assert metrics[0]['bytesOutCount'] > 0
        assert metrics[0]['messagesInCount'] > 0
        assert metrics[0]['topicSummary']['numOfPartitions'] == 10
        assert metrics[0]['topicSummary']['numOfBrokersForTopic'] == 1
        assert metrics[0]['topicSummary']['numOfReplicas'] == 1
        assert metrics[0]['topicSummary']['underReplicatedPercent'] == 0.0
        assert metrics[0]['topicSummary']['preferredReplicasPercent'] == 100.0


@retry_test(max_retries=300, wait_time_secs=1)
def test_smm_broker():
    resp = smm.api_get('/api/v1/admin/metrics/aggregated/brokers', params={'from': '-1', 'to': '-1'})
    brokers = resp.json()
    with exception_context(brokers):
        assert 'aggrBrokerMetricsCollection' in brokers
        assert len(brokers['aggrBrokerMetricsCollection']) == 1
        metrics = brokers['aggrBrokerMetricsCollection'][0]
        assert metrics['throughput'] > 0
        assert metrics['messageIn'] > 0


@retry_test(max_retries=300, wait_time_secs=1)
def test_smm_group():
    resp = smm.api_get('/api/v1/admin/metrics/aggregated/groups', params={'from': '-1', 'to': '-1'})
    groups = [g for g in resp.json() if g['consumerGroupInfo']['id'] == CONSUMER_GROUP_ID]
    assert len(groups) == 1
    group = groups[0]
    with exception_context(group):
        assert group['consumerGroupInfo']['state'] == 'Stable'
        assert group['consumerGroupInfo']['active'] is True
        assert 'iot' in group['wrappedPartitionMetrics']
        metrics = group['wrappedPartitionMetrics']['iot']
        for partition in metrics:
            assert metrics[partition]['partitionMetrics']['messagesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesOutCount'] > 0
            assert PRODUCER_CLIENT_ID in metrics[partition]['producerIdToOutMessagesCount']
            assert metrics[partition]['producerIdToOutMessagesCount'][PRODUCER_CLIENT_ID] > 0


@retry_test(max_retries=300, wait_time_secs=1)
def test_smm_producer():
    resp = smm.api_get('/api/v1/admin/metrics/aggregated/producers', params={'from': '-1', 'to': '-1'})
    producers = [p for p in resp.json() if p['clientId'] == PRODUCER_CLIENT_ID]
    assert len(producers) == 1
    producer = producers[0]
    with exception_context(producer):
        assert producer['latestOutMessagesCount'] > 0
        assert producer['active'] is True
        assert 'iot' in producer['wrappedPartitionMetrics']
        metrics = producer['wrappedPartitionMetrics']['iot']
        for partition in metrics:
            assert metrics[partition]['partitionMetrics']['messagesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesOutCount'] > 0


def _is_kafka_connect_configured():
    resp = smm.api_get('/api/v1/admin/kafka-connect/is-configured')
    assert resp.status_code == requests.codes.ok
    return resp.text == 'true'


@pytest.mark.skipif(not _is_kafka_connect_configured(), reason='Kafka Connect is not configured')
@retry_test(max_retries=3, wait_time_secs=1)
def test_smm_kafka_connect_workers():
    resp = smm.api_get('/api/v1/admin/metrics/connect/workers')
    workers = resp.json()
    with exception_context(workers):
        assert len(workers) == 1
        assert 'hostName' in workers[0]


@pytest.mark.skipif(not _is_kafka_connect_configured(), reason='Kafka Connect is not configured')
@retry_test(max_retries=3, wait_time_secs=1)
def test_smm_kafka_connect_connectors():
    resp = smm.api_get('/api/v1/admin/kafka-connect/connectors')
    connectors = resp.json()
    with exception_context(connectors):
        assert 'connectors' in connectors


@pytest.mark.skipif(not _is_kafka_connect_configured(), reason='Kafka Connect is not configured')
@retry_test(max_retries=3, wait_time_secs=1)
def test_smm_kafka_connect_plugins():
    resp = smm.api_get('/api/v1/admin/kafka-connect/connector-plugins')
    plugins = resp.json()
    with exception_context(plugins):
        assert EXPECTED_KAFKA_CONNECT_SINK_PLUGINS.issubset([p['class'] for p in plugins if p['type'] == 'sink'])
        assert EXPECTED_KAFKA_CONNECT_SOURCE_PLUGINS.issubset([p['class'] for p in plugins if p['type'] == 'source'])
