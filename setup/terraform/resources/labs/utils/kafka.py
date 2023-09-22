#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from . import *


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
