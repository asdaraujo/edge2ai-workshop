from ..utils import CONSUMER_GROUP_ID, PRODUCER_CLIENT_ID
from ..utils import smm_api_get, exception_context, retry_test

@retry_test(max_retries=120, wait_time_secs=1)
def test_smm_topic():
    resp = smm_api_get('/api/v1/admin/metrics/aggregated/topics', params={'from': '-1', 'to': '-1'})
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

@retry_test(max_retries=120, wait_time_secs=1)
def test_smm_broker():
    resp = smm_api_get('/api/v1/admin/metrics/aggregated/brokers', params={'from': '-1', 'to': '-1'})
    brokers = resp.json()
    with exception_context(brokers):
        assert 'aggrBrokerMetricsCollection' in brokers
        assert len(brokers['aggrBrokerMetricsCollection']) == 1
        metrics = brokers['aggrBrokerMetricsCollection'][0]
        assert metrics['throughput'] > 0
        assert metrics['messageIn'] > 0

@retry_test(max_retries=120, wait_time_secs=1)
def test_smm_group():
    resp = smm_api_get('/api/v1/admin/metrics/aggregated/groups', params={'from': '-1', 'to': '-1'})
    groups = [g for g in resp.json() if g['consumerGroupInfo']['id'] == CONSUMER_GROUP_ID]
    assert len(groups) == 1
    group = groups[0]
    with exception_context(group):
        assert group['consumerGroupInfo']['state'] == 'Stable'
        assert group['consumerGroupInfo']['active'] == True
        assert 'iot' in group['wrappedPartitionMetrics']
        metrics = group['wrappedPartitionMetrics']['iot']
        for partition in metrics:
            assert metrics[partition]['partitionMetrics']['messagesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesOutCount'] > 0
            assert PRODUCER_CLIENT_ID in metrics[partition]['producerIdToOutMessagesCount']
            assert metrics[partition]['producerIdToOutMessagesCount'][PRODUCER_CLIENT_ID] > 0

@retry_test(max_retries=120, wait_time_secs=1)
def test_smm_producer():
    resp = smm_api_get('/api/v1/admin/metrics/aggregated/producers', params={'from': '-1', 'to': '-1'})
    producers = [p for p in resp.json() if p['clientId'] == PRODUCER_CLIENT_ID]
    assert len(producers) == 1
    producer = producers[0]
    with exception_context(producer):
        assert producer['latestOutMessagesCount'] > 0
        assert producer['active'] == True
        assert 'iot' in producer['wrappedPartitionMetrics']
        metrics = producer['wrappedPartitionMetrics']['iot']
        for partition in metrics:
            assert metrics[partition]['partitionMetrics']['messagesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesInCount'] > 0
            assert metrics[partition]['partitionMetrics']['bytesOutCount'] > 0
