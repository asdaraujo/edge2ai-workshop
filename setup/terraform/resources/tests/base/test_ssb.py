#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing SSB
"""
import pytest
import requests
from ...labs import exception_context, retry_test
from ...labs.workshop_nifi import CONSUMER_GROUP_ID, PRODUCER_CLIENT_ID
from ...labs.utils import ssb, is_kerberos_enabled


@pytest.mark.skipif(not ssb.is_csa16_or_later() or not ssb.is_ssb_installed() or not is_kerberos_enabled(),
                    reason='CSA version is earlier than 1.6 or SSB is not deployed or Kerberos is not enabled')
def test_ssb_upload_keytab():
    ssb.upload_keytab('admin', '/keytabs/admin.keytab')


@pytest.mark.skipif(not ssb.is_csa17_or_later() or not ssb.is_ssb_installed() or not is_kerberos_enabled(),
                    reason='CSA version is earlier than 1.7 or SSB is not deployed or Kerberos is not enabled')
def test_ssb_generate_keytab():
    ssb.generate_keytab('admin', 'Supersecret1')

