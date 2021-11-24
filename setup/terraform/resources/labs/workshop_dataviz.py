#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
import os.path

from . import *
from .utils import dataviz

CONNECTION_TYPE = 'impyla'
CONNECTION_NAME = 'Local Impala'
CONNECTION_PARAMS = {
    "HOST": get_hostname(),
    "PORT": "21050",
    "MODE": "binary",
    "AUTH": "nosasl",
    "SOCK": "normal",
}
DATASET_NAME = 'sensor data1'

DATASET_EXPORT_FILE = 'visuals_dataset.json'
TABLE_VISUAL_EXPORT_FILE = 'visuals_table.json'
SCATTER_VISUAL_EXPORT_FILE = 'visuals_scatter.json'


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
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), DATASET_EXPORT_FILE))

    def lab4_create_table_visual(self):
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), TABLE_VISUAL_EXPORT_FILE))

    def lab5_create_scatter_visual(self):
        dataviz.import_artifacts(CONNECTION_NAME, os.path.join(self.get_artifacts_dir(), SCATTER_VISUAL_EXPORT_FILE))
