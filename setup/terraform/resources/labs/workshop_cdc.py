#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
from . import *
from .utils import ssb, postgres

POSTGRES_DB_NAME = 'cdc_test'
POSTGRES_DB_USR = 'cdc_user'
POSTGRES_DB_PWD = get_the_pwd()

DROP_TABLES = '''
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS trans_replica;
'''

DROP_SSB_TABLES = '''
DROP TABLE IF EXISTS transactions_cdc;
DROP TABLE IF EXISTS trans_replica;
DROP TABLE IF EXISTS trans_changelog;
'''

LAB1_CREATE_TABLE = '''
CREATE TABLE transactions (
  id INT,
  name TEXT,
  PRIMARY KEY (id)
);
ALTER TABLE transactions REPLICA IDENTITY FULL;
INSERT INTO transactions VALUES (100, 'flink is awesome');
SELECT * FROM transactions;
'''

LAB2_CREATE_SSB_TABLE = '''
CREATE TABLE transactions_cdc (
  id   INT,
  name STRING
) WITH (
  'connector' = 'postgres-cdc',
  'hostname' = '{hostname}',
  'username' = 'cdc_user',
  'password' = 'supersecret1',
  'database-name' = 'cdc_test',
  'table-name' = 'transactions',
  'schema-name' = 'public',
  'decoding.plugin.name' = 'pgoutput',
  'debezium.publication.name' = 'dbz_publication',
  'debezium.slot.name' = 'flink',
  'debezium.snapshot.mode' = 'initial'
);
'''.format(hostname=get_hostname())

LAB3_TRANSACTIONS = '''
INSERT INTO transactions
VALUES (101, 'SQL Stream Builder rocks!');

UPDATE transactions
SET name = 'Flink is really awesome!!!'
WHERE id = 100;
'''

LAB4_CREATE_TABLE = '''
CREATE TABLE trans_replica (
  id INT,
  name TEXT,
  PRIMARY KEY (id)
);
'''

LAB4_CREATE_SSB_TABLE = '''
CREATE TABLE `ssb`.`ssb_default`.`trans_replica` (
  `id` INT,
  `name` VARCHAR(2147483647),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:postgresql://{hostname}:5432/cdc_test',
  'table-name' = 'trans_replica',
  'password' = '{pwd}',
  'username' = 'cdc_user',
  'driver' = 'org.postgresql.Driver'
);
'''.format(pwd=get_the_pwd(), hostname=get_hostname())

LAB4_INSERT_INTO_REPLICA = '''
INSERT INTO trans_replica
SELECT *
FROM transactions_cdc;
'''

LAB5_CREATE_SSB_TABLE = '''
CREATE TABLE  `ssb`.`ssb_default`.`trans_changelog` (
  `id` INT,
  `name` VARCHAR(2147483647)
) WITH (
  'connector' = 'kafka',
  'properties.bootstrap.servers' = '{hostname}:9092',
  'topic' = 'trans_changelog',
  'key.format' = 'json',
  'key.fields' = 'id',
  'value.format' = 'debezium-json'
);
'''.format(hostname=get_hostname())

LAB5_INSERT_CHANGELOG = '''
INSERT INTO trans_changelog
SELECT *
FROM transactions_cdc;
'''

LAB5_TRANSACTIONS = '''
INSERT INTO transactions VALUES (200, 'This is an insert.');
UPDATE transactions SET name = 'This is an update.' WHERE id = 200;
DELETE FROM transactions WHERE id = 200;
'''

SR_PROVIDER_NAME = 'sr'
SR_PROVIDER_DATABASE_FILTER = '.*'
SR_PROVIDER_TABLE_FILTER = 'iot.*'

IOT_ENRICHED_TABLE = 'iot_enriched'
IOT_ENRICHED_TOPIC = 'iot_enriched'
IOT_ENRICHED_TS_COLUMN = 'sensor_ts'
IOT_ENRICHED_ROWTIME_COLUMN = 'event_time'
IOT_ENRICHED_GROUP_ID = 'ssb-iot-1'
IOT_ENRICHED_OFFSET = 'earliest'
IOT_ENRICHED_TRANSFORM = '''// parse the JSON record
var parsedVal = JSON.parse(record.value);
// Convert sensor_ts from micro to milliseconds
parsedVal['sensor_ts'] = Math.round(parsedVal['sensor_ts']/1000);
// serialize output as JSON
JSON.stringify(parsedVal);'''

IOT_ENRICHED_AVRO_TOPIC = 'iot_enriched_avro'

SCHEMA_URI = 'http://raw.githubusercontent.com/cloudera-labs/edge2ai-workshop/master/sensor.avsc'


class ChangeDataCaptureWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'cdc'

    @classmethod
    def prereqs(cls):
        """
        Return a list of prereqs for this workshop. The list can contain either:
          - Strings identifying the name of other workshops that need to be setup before this one does. In
            this case all the labs of the specified workshop will be setup.
          - Tuples (String, Integer), where the String specifies the name of the workshop and Integer the number
            of the last lab of that workshop to be executed/setup.
        """
        return []

    def before_setup(self):
        pass

    def after_setup(self):
        pass

    def teardown(self):
        ssb.stop_all_jobs()
        ssb.execute_sql(DROP_SSB_TABLES)
        postgres.execute_sql(DROP_TABLES, POSTGRES_DB_NAME, POSTGRES_DB_USR, POSTGRES_DB_PWD)
        # ssb.delete_table(IOT_ENRICHED_TABLE)
        # ssb.delete_data_provider(KAFKA_PROVIDER_NAME)

    def lab1_create_table(self):
        postgres.execute_sql(LAB1_CREATE_TABLE, POSTGRES_DB_NAME, POSTGRES_DB_USR, POSTGRES_DB_PWD)

    def lab2_create_ssb_cdc_table(self):
        ssb.execute_sql(LAB2_CREATE_SSB_TABLE)

    def lab3_capture_changes(self):
        ssb.execute_sql('SELECT * FROM transactions_cdc', job_name='lab3', sample_interval_millis=0)
        postgres.execute_sql(LAB3_TRANSACTIONS, POSTGRES_DB_NAME, POSTGRES_DB_USR, POSTGRES_DB_PWD)
        time.sleep(5)
        ssb.stop_job('lab3', wait_secs=3)

    def lab4_replicate_changes(self):
        postgres.execute_sql(LAB4_CREATE_TABLE, POSTGRES_DB_NAME, POSTGRES_DB_USR, POSTGRES_DB_PWD)
        ssb.execute_sql(LAB4_CREATE_SSB_TABLE)
        ssb.execute_sql(LAB4_INSERT_INTO_REPLICA, job_name='lab4', sample_interval_millis=0)
        time.sleep(5)
        ssb.stop_job('lab4', wait_secs=3)

    def lab5_capture_changelog(self):
        ssb.execute_sql(LAB5_CREATE_SSB_TABLE)
        ssb.execute_sql(LAB5_INSERT_CHANGELOG, job_name='lab5', sample_interval_millis=0)
        time.sleep(2)
        postgres.execute_sql(LAB5_TRANSACTIONS, POSTGRES_DB_NAME, POSTGRES_DB_USR, POSTGRES_DB_PWD)
        time.sleep(5)
        ssb.stop_job('lab5')
