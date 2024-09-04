#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing NiFi Workshop
"""
from ...labs.utils import nifi as nf

nf.set_environment()


def test_root_pg_disabled():
    assert nf.get_process_group('root').disabled_count == 0


def test_root_pg_invalid():
    assert nf.get_process_group('root').invalid_count == 0


def test_root_pg_stopped():
    assert nf.get_process_group('root').stopped_count == 0


def test_root_pg_failure():
    assert nf.get_process_group('root').sync_failure_count == 0


