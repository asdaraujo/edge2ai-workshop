#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
For preparation of the test suite
"""

import os
import pytest
from ..utils import *


@pytest.fixture(scope="session")
def schema_text():
    if 'SCHEMA_FILE' in os.environ and os.path.exists(os.environ['SCHEMA_FILE']):
        return open(os.environ['SCHEMA_FILE']).read()
    raise RuntimeError('Environment variable SCHEMA_FILE is not set.')


@pytest.fixture(scope="session")
def setup_flag():
    if 'SKIP_SETUP' in os.environ:
        return False
    return True


@pytest.fixture(scope="session")
def cdsw_flag():
    if 'SKIP_CDSW' in os.environ:
        return False
    return True


@pytest.fixture(scope="session")
def teardown_flag():
    if 'SKIP_TEARDOWN' in os.environ:
        return False
    return True


@pytest.fixture(scope="session")
def run_id():
    if 'RUN_ID' in os.environ:
        return os.environ['RUN_ID']
    run_id =  str(int(time.time()))
    print('RUN_ID=' + run_id)
    return run_id


@pytest.fixture(scope="session", autouse=True)
def setup_all(run_id, schema_text, setup_flag, teardown_flag, cdsw_flag):
    if setup_flag:
        global_teardown(run_id)
        global_setup(run_id, schema_text, cdsw_flag)
    else:
        set_environment(run_id)
    yield True
    if teardown_flag:
        global_teardown(run_id)


