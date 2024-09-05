#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from . import *
from kafka import KafkaConsumer


def _get_port():
    return '9093' if is_tls_enabled() else '9092'


def get_bootstrap_servers(hostname=None):
    if not hostname:
        hostname = get_hostname()
    return hostname + ':' + _get_port()


def get_security_protocol():
    if is_tls_enabled():
        if is_kerberos_enabled():
            return 'SASL_SSL'
        else:
            return 'SSL'
    else:
        if is_kerberos_enabled():
            return 'SASL_PLAINTEXT'
        else:
            return 'PLAINTEXT'


def get_common_client_properties(env, client_type, consumer_group_id, client_id):
    props = {
        'bootstrap.servers': get_bootstrap_servers(),
        'security.protocol': get_security_protocol(),
        'sasl.mechanism': 'GSSAPI',
        'sasl.kerberos.service.name': 'kafka',
    }
    if client_type == 'producer':
        props.update({
            'use-transactions': 'false',
            'attribute-name-regex': 'schema.*',
            'client.id': client_id,
        })
    else:  # consumer
        props.update({
            'honor-transactions': 'false',
            'group.id': consumer_group_id,
            'auto.offset.reset': 'latest',
            'header-name-regex': 'schema.*',
        })
    if is_tls_enabled():
        props.update({
            'kerberos-credentials-service': env.keytab_svc.id,
            'ssl.context.service': env.ssl_svc.id,
        })
    return props


def _get_kafka_client_properties():
    props = {
        'bootstrap_servers': get_bootstrap_servers(),
        'security_protocol': get_security_protocol(),
    }
    if is_kerberos_enabled():
        props.update({
            'sasl_mechanism': 'GSSAPI',
            'sasl_kerberos_service_name': 'kafka',
        })
    if is_tls_enabled():
        props.update({
            'ssl_cafile': get_pem_truststore_path(),
        })
    return props


def _get_kafka_consumer_properties(auto_offset_reset, enable_auto_commit):
    props = _get_kafka_client_properties()
    props.update({
        'auto_offset_reset': auto_offset_reset,
        'enable_auto_commit': enable_auto_commit,
    })
    return props


def get_consumer(auto_offset_reset='latest', enable_auto_commit=True):
    return KafkaConsumer(**_get_kafka_consumer_properties(auto_offset_reset, enable_auto_commit))


def consume_topic(topic, stop_after=1, timeout_secs=10):
    consumer = get_consumer()
    consumer.subscribe([topic])

    records = []
    start_time = time.time()
    while True:
        resp = consumer.poll(timeout_ms=1000)
        for tp, msgs in resp.items():
            records.extend(msgs)
        if (time.time() > start_time + timeout_secs) or len(records) >= stop_after:
            return records
