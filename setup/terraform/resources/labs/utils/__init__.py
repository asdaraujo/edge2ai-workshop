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
