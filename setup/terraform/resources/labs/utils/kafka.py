#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from . import *


def _get_port():
    return '9093' if is_tls_enabled() else '9092'


def _get_bootstrap_servers():
    return get_hostname() + ':' + _get_port()


def get_common_client_properties(env, client_type, consumer_group_id, client_id):
    props = {
        'bootstrap.servers': _get_bootstrap_servers(),
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
            'sasl.kerberos.service.name': 'kafka',
            'sasl.mechanism': 'GSSAPI',
            'security.protocol': 'SASL_SSL',
            'ssl.context.service': env.ssl_svc.id,
        })
    return props
