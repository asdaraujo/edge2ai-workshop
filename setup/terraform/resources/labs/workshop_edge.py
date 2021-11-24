#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
from nipyapi import canvas, versioning, nifi
from nipyapi.nifi.rest import ApiException

from . import *
from .utils import efm, schreg, nifireg, nifi as nf, kafka, kudu, cdsw

PG_NAME = 'Process Sensor Data'
CONSUMER_GROUP_ID = 'iot-sensor-consumer'
PRODUCER_CLIENT_ID = 'nifi-sensor-data'


class EdgeWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'edge'

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
        self.context.root_pg, self.context.efm_pg_id, self.context.flow_id = nf.set_environment()

    def after_setup(self):
        nf.wait_for_data(PG_NAME)

    def teardown(self):
        root_pg, _, flow_id = nf.set_environment()

        canvas.schedule_process_group(root_pg.id, False)
        while True:
            failed = False
            for controller in canvas.list_all_controllers(root_pg.id):
                try:
                    canvas.schedule_controller(controller, False)
                    LOG.debug('Controller %s stopped.', controller.component.name)
                except ApiException as exc:
                    if exc.status == 409 and 'is referenced by' in exc.body:
                        LOG.debug('Controller %s failed to stop. Will retry later.', controller.component.name)
                        failed = True
            if not failed:
                break

        nf.delete_all(root_pg)
        efm.delete_all(flow_id)
        schreg.delete_all_schemas()
        reg_client = versioning.get_registry_client('NiFi Registry')
        if reg_client:
            versioning.delete_registry_client(reg_client)
        nifireg.delete_flows('SensorFlows')
        kudu.drop_table()

    def lab1_sensor_simulator(self):
        # Create a processor to run the sensor simulator
        gen_data = nf.create_processor(
            self.context.root_pg, 'Generate Test Data', 'org.apache.nifi.processors.standard.ExecuteProcess',
            (0, 0),
            {
                'properties': {
                    'Command': 'python3',
                    'Command Arguments': '/opt/demo/simulate.py',
                },
                'schedulingPeriod': '1 sec',
                'schedulingStrategy': 'TIMER_DRIVEN',
                'autoTerminatedRelationships': ['success'],
            })
        canvas.schedule_processor(gen_data, True)

    def lab2_edge_flow(self):
        # Create input port and funnel in NiFi
        self.context.from_gw = canvas.create_port(
            self.context.root_pg.id, 'INPUT_PORT', 'from Gateway', 'STOPPED', (0, 200))
        self.context.temp_funnel = nf.create_funnel(self.context.root_pg.id, (96, 350))
        canvas.create_connection(self.context.from_gw, self.context.temp_funnel)
        canvas.schedule_components(self.context.root_pg.id, True, [self.context.from_gw])

        # Create flow in EFM
        self.context.consume_mqtt = efm.create_processor(
            self.context.flow_id, self.context.efm_pg_id,
            'ConsumeMQTT',
            'org.apache.nifi.processors.mqtt.ConsumeMQTT',
            (100, 100),
            {
                'Broker URI': 'tcp://{hostname}:1883'.format(hostname=get_hostname()),
                'Client ID': 'minifi-iot',
                'Topic Filter': 'iot/#',
                'Max Queue Size': '60',
            })
        self.context.nifi_rpg = efm.create_remote_processor_group(
            self.context.flow_id, self.context.efm_pg_id, 'Remote PG', nf.get_url(),
            'HTTP', (100, 400))
        self.context.consume_conn = efm.create_connection(
            self.context.flow_id, self.context.efm_pg_id, self.context.consume_mqtt, 'PROCESSOR',
            self.context.nifi_rpg,
            'REMOTE_INPUT_PORT', ['Message'], destination_port=self.context.from_gw.id,
            name='Sensor data', flow_file_expiration='60 seconds')

        # Create a bucket in NiFi Registry to save the edge flow versions
        if not versioning.get_registry_bucket('IoT'):
            versioning.create_registry_bucket('IoT')

        # Publish/version the flow
        efm.publish_flow(self.context.flow_id, 'First version - {}'.format(self.run_id))

    def lab3_expand_edge_flow(self):
        # Expand the CEM flow
        extract_proc = efm.create_processor(
            self.context.flow_id, self.context.efm_pg_id,
            'Extract sensor_0 and sensor1 values',
            'org.apache.nifi.processors.standard.EvaluateJsonPath',
            (500, 100),
            {
                'Destination': 'flowfile-attribute',
                'sensor_0': '$.sensor_0',
                'sensor_1': '$.sensor_1',
            },
            auto_terminate=['failure', 'unmatched', 'sensor_0', 'sensor_1'])
        filter_proc = efm.create_processor(
            self.context.flow_id, self.context.efm_pg_id,
            'Filter Errors',
            'org.apache.nifi.processors.standard.RouteOnAttribute',
            (500, 400),
            {
                'Routing Strategy': 'Route to Property name',
                'error': '${sensor_0:ge(500):or(${sensor_1:ge(500)})}',
            },
            auto_terminate=['error'])
        efm.delete_by_type(self.context.flow_id, self.context.consume_conn, 'connections')
        self.context.consume_conn = efm.create_connection(
            self.context.flow_id, self.context.efm_pg_id, self.context.consume_mqtt,
            'PROCESSOR', extract_proc, 'PROCESSOR', ['Message'],
            name='Sensor data',
            flow_file_expiration='60 seconds')
        efm.create_connection(
            self.context.flow_id, self.context.efm_pg_id, extract_proc,
            'PROCESSOR', filter_proc, 'PROCESSOR', ['matched'],
            name='Extracted attributes',
            flow_file_expiration='60 seconds')
        efm.create_connection(
            self.context.flow_id, self.context.efm_pg_id, filter_proc,
            'PROCESSOR', self.context.nifi_rpg, 'REMOTE_INPUT_PORT', ['unmatched'],
            destination_port=self.context.from_gw.id,
            name='Valid data',
            flow_file_expiration='60 seconds')

        # Publish/version flow
        efm.publish_flow(self.context.flow_id, 'Second version - {}'.format(self.run_id))
