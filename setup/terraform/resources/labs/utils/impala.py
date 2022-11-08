#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
from impala.dbapi import connect
from impala.error import ProgrammingError
from . import *


def _connect_to_impala():
    if is_tls_enabled():
        params = {
            'auth_mechanism': 'GSSAPI',
            'kerberos_service_name': 'impala',
            'use_ssl': True,
            'ca_cert': get_truststore_path(),
        }
    else:
        params = {}
    return connect(host=get_hostname(), port=21050, **params)


def execute_sql(stmt):
    conn = _connect_to_impala()
    cursor = conn.cursor()
    cursor.execute(stmt)
    try:
        results = cursor.fetchall()
    except ProgrammingError as exc:
        if exc.args and exc.args[0] == 'Trying to fetch results on an operation with no results.':
            return None
        raise
    return results
