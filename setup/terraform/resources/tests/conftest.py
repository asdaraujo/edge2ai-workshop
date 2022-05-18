#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
For preparation of the test suite
"""

import os
import pytest
from ..labs import *

_LAST_WORKSHOP = None


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


@pytest.fixture(scope="module", autouse=True)
def setup_all(setup_flag, teardown_flag, run_id, request):
    global _LAST_WORKSHOP
    module_path = os.path.dirname(request.module.__file__)
    workshop = os.path.basename(module_path)
    if setup_flag:
        if _LAST_WORKSHOP != workshop:
            print('\nTEARDOWN:{}:{}\n'.format(run_id, _LAST_WORKSHOP if _LAST_WORKSHOP else 'GLOBAL'))
            workshop_teardown(target_workshop=_LAST_WORKSHOP, run_id=run_id)

            if not is_workshop_runnable(workshop):
                pytest.skip('Workshop [{}] is not runnable.'.format(workshop))

            print('\nSETUP:{}:{}\n'.format(run_id, workshop))
            workshop_setup(target_workshop=workshop, run_id=run_id, ignore=True)
            _LAST_WORKSHOP = workshop


@pytest.fixture(scope="session", autouse=True)
def final_teardown(setup_flag, teardown_flag, run_id, request):
    global _LAST_WORKSHOP
    yield True
    if teardown_flag and _LAST_WORKSHOP:
        print('\nTEARDOWN:{}:{}\n'.format(run_id, _LAST_WORKSHOP))
        workshop_teardown(target_workshop=_LAST_WORKSHOP, run_id=run_id, ignore=True)


