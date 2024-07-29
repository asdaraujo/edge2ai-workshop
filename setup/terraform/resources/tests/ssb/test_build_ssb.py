#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing SSB Workshop
"""
from ...labs.utils import kafka


def test_ssb_build():
    assert True


def test_ssb_check_data():
    for topic in ['iot', 'iot_enriched', 'iot_enriched_avro']:
        assert len(kafka.consume_topic(topic, timeout_secs=10)) > 0, f'No activity in topic {topic}'
