#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing SSB Workshop
"""
from ...labs.utils import kafka, ssb


def test_ssb_build():
    assert True


def test_ssb_check_data():
    for topic in ['iot', 'iot_enriched', 'iot_enriched_avro']:
        assert len(kafka.consume_topic(topic, timeout_secs=10)) > 0, f'No activity in topic {topic}'


def test_ssb_get_providers():
    ssb.use_load_balancer = False
    ssb.use_knox = True
    assert len(ssb.get_data_providers('Local Kafka')) == 1
