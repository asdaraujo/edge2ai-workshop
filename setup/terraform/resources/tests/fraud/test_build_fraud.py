#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing NiFi Workshop
"""
from ...labs.utils import nifi as nf

nf.set_environment()


def test_pg():
    assert nf.check_for_processor_activity('Fraud Detection', entity_type='pg', metric='queued_count', absolute_value=0,
                                           is_greater_than_threshold=False)


def test_root_pg_disabled():
    assert nf.get_process_group('root').disabled_count == 0


def test_root_pg_invalid():
    assert nf.get_process_group('root').invalid_count == 0


def test_root_pg_stopped():
    assert nf.get_process_group('root').stopped_count == 0


def test_root_pg_failure():
    assert nf.get_process_group('root').sync_failure_count == 0


def test_kudu_output_activity():
    assert nf.check_for_processor_activity('Write to Kudu', delta=3)


def test_transaction_output_activity():
    assert nf.check_for_processor_activity('Publish to Kafka topic: transactions', delta=3)


def test_fraud_output_activity():
    assert nf.check_for_processor_activity('Publish to Kafka topic: frauds', delta=3)
