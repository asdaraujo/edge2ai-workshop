#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import urllib3

from .. import *

# Avoid unverified TLS warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def enable_debug():
    LOG.setLevel(logging.DEBUG)


def disable_debug():
    LOG.setLevel(logging.INFO)


def get_public_ip():
    retries = 3
    while retries > 0:
        resp = requests.get('http://ifconfig.me')
        if resp.status_code == requests.codes.ok:
            return resp.text
        retries -= 1
        time.sleep(1)
    raise RuntimeError('Failed to get the public IP address.')
