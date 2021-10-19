#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
For preparation of the test suite
"""

import os
import pytest
from ..labs import *


@pytest.fixture(scope="session")
def setup_flag():
    if 'SKIP_SETUP' in os.environ:
        return False
    return True


# @pytest.fixture(scope="session")
# def cdsw_flag():
#     if 'SKIP_CDSW' in os.environ:
#         return False
#     return True


@pytest.fixture(scope="session")
def teardown_flag():
    if 'SKIP_TEARDOWN' in os.environ:
        return False
    return True


@pytest.fixture(scope="session")
def run_id():
    return get_run_id()


@pytest.fixture(scope="session", autouse=True)
def setup_all(setup_flag, teardown_flag, run_id):
    print('SETUP_ALL:{}'.format(run_id))
    if setup_flag:
        global_teardown(run_id=run_id)
        global_setup(run_id=run_id)
    yield True
    if teardown_flag:
        global_teardown(run_id=run_id)


