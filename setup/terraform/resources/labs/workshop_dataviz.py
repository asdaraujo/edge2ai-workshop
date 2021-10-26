#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
import json
import os.path

from nipyapi import canvas, versioning, nifi
from nipyapi.nifi.rest import ApiException

from . import *
from .utils import dataviz

CONNECTION_TYPE = 'impyla'
CONNECTION_NAME = 'Local Impala1'
CONNECTION_PARAMS = {
    "HOST": "cdp.52.26.198.174.nip.io",
    "PORT": "21050",
    "MODE": "binary",
    "AUTH": "nosasl",
    "SOCK": "normal",
}
DATASET_NAME = 'sensor data1'

DATASET_EXPORT_FILE = 'visuals_dataset.json'
TABLE_VISUAL_EXPORT_FILE = 'visuals_table.json'
SCATTER_VISUAL_EXPORT_FILE = 'visuals_scatter.json'

def skip_cdsw():
    flag = 'SKIP_CDSW' in os.environ
    LOG.debug('SKIP_CDSW={}'.format(flag))
    return flag


class DataVizWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'dataviz'

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

    def before_setup(self):
        pass

    def after_setup(self):
        pass

    def teardown(self):
        dataviz.delete_dataset(dc_name=CONNECTION_NAME)
        dataviz.delete_connection(dc_name=CONNECTION_NAME)

    def lab2_create_connection(self):
        dataviz.create_connection(CONNECTION_TYPE, CONNECTION_NAME, CONNECTION_PARAMS)

    def lab3_create_dataset(self):
        # conn = dataviz.get_connection(CONNECTION_NAME)
        #
        # params = {
        #     'dataconnection_id': conn['id'],
        #     'dataset_name': DATASET_NAME,
        #     'dataset_type': 'singletable',
        #     'dataset_info': json.dumps([
        #         {
        #             'tablename': 'default.sensors',
        #             'columns': [
        #                 {'name': 'sensor_id', 'type': 'INT', 'isdim': True, 'alias': 'sensor_id'},
        #                 {
        #                     'name': '',
        #                     'type': 'TIMESTAMP',
        #                     'isdim': True,
        #                     'alias': 'sensor_timestamp',
        #                     'basecol': 'sensor_ts',
        #                     'expr': 'microseconds_add(to_timestamp(cast([sensor_ts]/1000000 as bigint)), [sensor_ts] % 1000000)',
        #                 },
        #                 {'name': 'sensor_ts', 'type': 'BIGINT', 'isdim': False, 'alias': 'sensor_ts'},
        #                 {'name': 'sensor_0', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_0'},
        #                 {'name': 'sensor_1', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_1'},
        #                 {'name': 'sensor_2', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_2'},
        #                 {'name': 'sensor_3', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_3'},
        #                 {'name': 'sensor_4', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_4'},
        #                 {'name': 'sensor_5', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_5'},
        #                 {'name': 'sensor_6', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_6'},
        #                 {'name': 'sensor_7', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_7'},
        #                 {'name': 'sensor_8', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_8'},
        #                 {'name': 'sensor_9', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_9'},
        #                 {'name': 'sensor_10', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_10'},
        #                 {'name': 'sensor_11', 'type': 'DOUBLE', 'isdim': False, 'alias': 'sensor_11'},
        #                 {'name': 'is_healthy', 'type': 'INT', 'isdim': False, 'alias': 'is_healthy'},
        #             ]
        #         }
        #     ]),
        #     'dataset_detail': 'default.sensors',
        #     'foreign_keys': '[["default.sensors", {}]]'
        # }
        # dataviz.create_dataset(params)
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), DATASET_EXPORT_FILE))

    def lab4_create_table_visual(self):
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), TABLE_VISUAL_EXPORT_FILE))

    def lab5_create_scatter_visual(self):
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), SCATTER_VISUAL_EXPORT_FILE))
