#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
from . import *
from .utils import ssb, schreg, kafka

TRUSTSTORE_PATH = '/opt/cloudera/security/jks/truststore.jks'
KAFKA_PROVIDER_NAME = 'edge2ai-kafka'

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


def read_schema():
    global SCHEMA_URI
    resp = requests.get(SCHEMA_URI)
    if resp.status_code == 200:
        return resp.text
    raise ValueError("Unable to retrieve schema from URI, response was %s", resp.status_code)


class SqlStreamBuilderWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'ssb'

    @classmethod
    def prereqs(cls):
        """
        Return a list of prereqs for this workshop. The list can contain either:
          - Strings identifying the name of other workshops that need to be setup before this one does. In
            this case all the labs of the specified workshop will be setup.
          - Tuples (String, Integer), where the String specifies the name of the workshop and Integer the number
            of the last lab of that workshop to be executed/setup.
        """
        return ['nifi']

    @classmethod
    def is_runnable(cls):
        """
        Return True is the workshop is runnable (i.e. all the necessary prerequisites are satisfied).
        This method can be overriden to check for necessary prerequisites.
        """
        return ssb.is_ssb_installed() and ssb.is_csa16_or_later()

    def before_setup(self):
        if is_kerberos_enabled():
            ssb.upload_keytab('admin', '/keytabs/admin.keytab')

    def after_setup(self):
        pass

    def teardown(self):
        ssb.delete_data_provider(SR_PROVIDER_NAME)
        try:
            schreg.delete_schema(IOT_ENRICHED_AVRO_TOPIC)
        except RuntimeError:
            pass # ignore if schema does not exist
        ssb.delete_table(IOT_ENRICHED_TABLE)
        ssb.delete_data_provider(KAFKA_PROVIDER_NAME)

    def lab1_create_kafka_data_provider(self):
        if is_tls_enabled():
            if is_kerberos_enabled():
                protocol = 'sasl'
            else:
                protocol = 'ssl'
        else:
            if is_kerberos_enabled():
                protocol = 'sasl_plaintext'
            else:
                protocol = 'plaintext'
        props = {
            'brokers': kafka.get_bootstrap_servers(),
            'protocol': protocol,
            'username': None,
            'password': None,
            'mechanism': 'KERBEROS',
            'ssl.truststore.location': TRUSTSTORE_PATH,
        }
        ssb.create_data_provider(KAFKA_PROVIDER_NAME, 'kafka', props)

    def lab2_create_iot_enriched_table(self):
        ssb.create_kafka_table(
            IOT_ENRICHED_TABLE, 'JSON',
            KAFKA_PROVIDER_NAME, IOT_ENRICHED_TOPIC,
            transform_code=IOT_ENRICHED_TRANSFORM,
            timestamp_column=IOT_ENRICHED_TS_COLUMN,
            rowtime_column=IOT_ENRICHED_ROWTIME_COLUMN,
            kafka_properties={
                'group.id': IOT_ENRICHED_GROUP_ID,
                'auto.offset.reset': IOT_ENRICHED_OFFSET,
            })

    def lab3_schema_registry_integration(self):
        schreg.create_schema(
            IOT_ENRICHED_AVRO_TOPIC, 'Schema for the data in the iot_enriched_avro topic', read_schema())

        provider = ssb.get_data_providers(KAFKA_PROVIDER_NAME)[0]
        # try:
        #     provider_id = provider['provider_id']
        # except:
        #     print(provider)
        #     raise
        provider_id = provider.get('provider_id', provider.get('id'))  # property name changed in CSA 1.9
        props = {
            'catalog_type': 'registry',
            'kafka.provider.id': provider_id,
            'registry.address': schreg.get_api_url(),
            'table_filters': [
                {
                    'database_filter': SR_PROVIDER_DATABASE_FILTER,
                    'table_filter': SR_PROVIDER_TABLE_FILTER,
                }
            ],
        }
        ssb.create_data_provider(SR_PROVIDER_NAME, 'catalog', props)
