#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing DataViz Applications
"""
import pytest
from ...labs import exception_context
from ...labs.utils import cdsw, vizapps

VIZ_PROJECT_NAME = 'VizApps Workshop'
VIZ_APP_NAME = 'Viz Server Application'


def _is_vizapps_deployed():
    return cdsw.get_release() >= [1, 10]


@pytest.mark.skipif(not _is_vizapps_deployed(), reason='VizApps is not deployed')
def test_vizapps_project_existence():
    app = cdsw.get_application(project_name=VIZ_PROJECT_NAME, app_name=VIZ_APP_NAME)
    with exception_context(app):
        assert app.get('url', None)


@pytest.mark.skipif(not _is_vizapps_deployed(), reason='VizApps is not deployed')
def test_vizapps_get_users():
    users = vizapps.get_users()
    with exception_context(users):
        usernames = [u['username'] for u in users]
        assert 'vizapps_admin' in usernames
        assert 'admin' in usernames
