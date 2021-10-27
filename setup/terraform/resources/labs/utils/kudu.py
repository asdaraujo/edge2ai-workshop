#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
from impala.dbapi import connect
from requests_gssapi import HTTPSPNEGOAuth
from . import *

_CREATE_KUDU_TABLE = """
CREATE TABLE IF NOT EXISTS sensors
(
 sensor_id INT,
 sensor_ts BIGINT,
 sensor_0 DOUBLE,
 sensor_1 DOUBLE,
 sensor_2 DOUBLE,
 sensor_3 DOUBLE,
 sensor_4 DOUBLE,
 sensor_5 DOUBLE,
 sensor_6 DOUBLE,
 sensor_7 DOUBLE,
 sensor_8 DOUBLE,
 sensor_9 DOUBLE,
 sensor_10 DOUBLE,
 sensor_11 DOUBLE,
 is_healthy INT,
 PRIMARY KEY (sensor_ID, sensor_ts)
)
PARTITION BY HASH PARTITIONS 16
STORED AS KUDU
TBLPROPERTIES ('kudu.num_tablet_replicas' = '1');
"""

_DROP_KUDU_TABLE = "DROP TABLE IF EXISTS sensors;"


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


def create_table():
    conn = _connect_to_impala()
    cursor = conn.cursor()
    cursor.execute(_CREATE_KUDU_TABLE)
    result = cursor.fetchall()
    if not any(x in str(result) for x in ["Table has been created", "Table already exists"]):
        raise RuntimeError('Failed to create Kudu table, response was:', str(result))


def drop_table():
    conn = _connect_to_impala()
    cursor = conn.cursor()
    cursor.execute(_DROP_KUDU_TABLE)
    result = cursor.fetchall()
    if not any(x in str(result) for x in ["Table has been dropped", "Table does not exist"]):
        raise RuntimeError('Failed to drop Kudu table, response was:', str(result))


def get_kudu_table_name(database_name, table_name):
    conn = _connect_to_impala()
    cursor = conn.cursor()
    cursor.execute('DESCRIBE EXTENDED `{}`.`{}`'.format(database_name, table_name))
    result = cursor.fetchall()
    for _, col2, col3 in result:
        if col2 and col3 and col2.strip() == 'kudu.table_name':
            return col3.strip()
    return None


def get_version():
    if is_tls_enabled():
        resp = requests.get('https://' + get_hostname() + ':8051/', verify=False, auth=HTTPSPNEGOAuth())
    else:
        resp = requests.get('http://' + get_hostname() + ':8051/')

    if resp:
        m = re.search('<h2>Version Info</h2>\n<pre>kudu ([0-9.]+)', resp.text)
        if m:
            version, = m.groups()
            version = tuple(map(lambda v: int(v), version.split('.')))
            return version

    return 999, 999, 999
