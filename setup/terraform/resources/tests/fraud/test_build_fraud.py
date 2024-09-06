#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing NiFi Workshop
"""
from ...labs.utils import nifi as nf

nf.set_environment()


def test_pg_statuses():
    expected_counts_by_status = {
        'disabled_count': 0,
        'invalid_count': 0,
        'running_count': 13,
        'stale_count': 0,
        'stopped_count': 0,
        'sync_failure_count': 0,
        'up_to_date_count': 0,
    }
    for metric, expected_value in expected_counts_by_status.items():
        assert nf.check_metric_value('Fraud Detection', nf.EQ(expected_value), entity_type='pg',
                                     metric=metric)


def test_root_pg_disabled():
    assert nf.get_process_group('root').disabled_count == 0


def test_root_pg_invalid():
    assert nf.get_process_group('root').invalid_count == 0


def test_root_pg_stopped():
    assert nf.get_process_group('root').stopped_count == 0


def test_root_pg_failure():
    assert nf.get_process_group('root').sync_failure_count == 0


def test_kudu_output_activity():
    assert nf.check_metric_delta('Write to Kudu', nf.GT(3))


def test_transaction_output_activity():
    assert nf.check_metric_delta('Publish to Kafka topic: transactions', nf.GT(3))


def test_fraud_output_activity():
    assert nf.check_metric_delta('Publish to Kafka topic: frauds', nf.GT(1), timeout_secs=300)
