#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import logging
import os
import re
import socket
import time
from abc import ABCMeta, abstractmethod
from contextlib import contextmanager
from datetime import datetime
from importlib import import_module
from inspect import getmembers

import requests

logging.basicConfig(level=logging.WARN)
LOG = logging.getLogger(__package__)
LOG.setLevel(logging.INFO)

# Global constants
LAB_METHOD_NAME_REGEX = r'lab([0-9]+)'
RUN_ID_ENV_VAR = 'RUN_ID'
THE_PWD_ENV_VAR = 'THE_PWD'
THE_PWD_FILE_NAME = 'the_pwd.txt'
ENABLE_TLS_FILE_NAME = '.enable-tls'
DEFAULT_TRUSTSTORE_PATH = '/opt/cloudera/security/x509/truststore.pem'
WORKSHOPS = {}


def _get_step_number(method_name):
    match = re.match(LAB_METHOD_NAME_REGEX, method_name)
    if match is None:
        return None
    return int(match.groups()[0])


def get_base_dir():
    return os.path.dirname(__file__) if os.path.dirname(__file__) else '.'


def get_run_id():
    if RUN_ID_ENV_VAR in os.environ:
        rid = os.environ[RUN_ID_ENV_VAR]
    else:
        rid = str(int(time.time()))
    LOG.debug('RUN_ID={}'.format(rid))
    return rid


def _get_parent_dir(path):
    return os.path.realpath(os.path.join(path, '..'))


def get_the_pwd():
    if THE_PWD_ENV_VAR in os.environ:
        return os.environ[THE_PWD_ENV_VAR]

    return _get_the_pwd_from_file(get_base_dir())


def _get_the_pwd_from_file(path):
    if path == '/':
        raise RuntimeError('Cannot get The Pwd. Please set the THE_PWD env variable.')

    file_path = os.path.join(path, THE_PWD_FILE_NAME)
    if os.path.exists(file_path):
        return open(file_path).read()
    else:
        return _get_the_pwd_from_file(_get_parent_dir(path))


def get_truststore_path():
    return DEFAULT_TRUSTSTORE_PATH


def is_tls_enabled(path=None):
    if path is None:
        path = get_base_dir()

    if path == '/':
        return False
    elif os.path.exists(os.path.join(path, ENABLE_TLS_FILE_NAME)):
        return True
    else:
        return is_tls_enabled(_get_parent_dir(path))


def get_hostname():
    return socket.gethostname()


def get_url_scheme():
    return 'https' if is_tls_enabled() else 'http'


def api_request(method, url, expected_code=requests.codes.ok, auth=None, **kwargs):
    truststore = get_truststore_path() if is_tls_enabled() else None
    LOG.debug('Request: method: %s, url: %s, auth: %s, verify: %s, kwargs: %s',
              method, url, 'yes' if auth else 'no', truststore, kwargs)
    resp = requests.request(method, url, auth=auth, verify=truststore, **kwargs)
    if resp.status_code != expected_code:
        raise RuntimeError('Request to URL %s returned code %s (expected was %s), Response: %s' % (
            resp.url, resp.status_code, expected_code, resp.text))
    return resp


class AbstractWorkshopMeta(ABCMeta):
    def __init__(cls, name, bases, dct):
        type.__init__(cls, name, bases, dct)
        if cls.workshop_id():
            WORKSHOPS[cls.workshop_id()] = cls


class AbstractWorkshop(metaclass=AbstractWorkshopMeta):
    def __init__(self, run_id=None, context=None):
        class _Context(object):
            pass

        self.context = context or _Context()
        self.run_id = run_id if run_id is not None else get_run_id()

    @classmethod
    @abstractmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        pass

    @classmethod
    @abstractmethod
    def prereqs(cls):
        """
        Return a list of prereqs for this workshop. The list can contain either:
          - Strings identifying the name of other workshops that need to be setup before this one does. In
            this case all the labs of the specified workshop will be setup.
          - Tuples (String, Integer), where the String specifies the name of the workshop and Integer the number
            of the last lab of that workshop to be executed/setup.
        """
        pass

    def before_setup(self):
        pass

    def after_setup(self):
        pass

    @abstractmethod
    def teardown(self):
        pass

    def _execute_prereqs(self):
        global WORKSHOPS
        for prereq in self.prereqs():
            if isinstance(prereq, str):
                workshop = prereq
                lab = 99
            else:
                workshop, lab = prereq

            LOG.info('Executing prereqs setup: Workshop {}, Lab < {}'.format(workshop, lab))
            WORKSHOPS[workshop](self.run_id, self.context).setup(lab)

    def setup(self, target_lab=99):
        self._execute_prereqs()
        self.before_setup()
        lab_setup_functions = [(n, f, _get_step_number(n)) for n, f in
                               getmembers(self.__class__) if _get_step_number(n) is not None]
        LOG.debug("Found Lab Setup Functions: %s", str(map(lambda x: x[2], lab_setup_functions)))
        for func_name, func, lab_number in lab_setup_functions:
            if lab_number < target_lab:
                LOG.info("Executing {}::{}".format(self.workshop_id(), func_name))
                func(self)
            else:
                LOG.debug("[{0}] is numbered higher than target [lab{1}], skipping".format(func_name, target_lab))
        self.after_setup()
        return self.context

    def get_artifacts_dir(self):
        return os.path.join(os.path.dirname(__file__), 'artifacts', self.workshop_id())

def _load_workshops():
    base_dir = get_base_dir()
    for f in os.listdir(base_dir):
        if f.startswith('workshop_') and os.path.isfile(os.path.join(base_dir, f)):
            f = '.' + f.replace('.py', '')
            import_module(f, package=__package__)


def global_setup(target_workshop='base', target_lab=99, run_id=None):
    _load_workshops()
    if target_workshop in WORKSHOPS:
        LOG.info('Executing setup for Lab {} in Workshop {}'.format(target_workshop, target_lab))
        WORKSHOPS[target_workshop](run_id).setup(target_lab)
    else:
        raise RuntimeError("Workshop [{}] not found. Known workshops are: {}".format(target_workshop, WORKSHOPS))
    LOG.info('Global setup completed successfully!')


def global_teardown(target_workshop=None, run_id=None):
    _load_workshops()
    if target_workshop is not None:
        LOG.info('Executing teardown for Workshop {}'.format(target_workshop))
        WORKSHOPS[target_workshop](run_id).teardown()
    else:
        for target_workshop in WORKSHOPS:
            LOG.info('Executing teardown for Workshop {}'.format(target_workshop))
            WORKSHOPS[target_workshop](run_id).teardown()
    LOG.info('Global teardown completed successfully!')


@contextmanager
def exception_context(obj):
    try:
        yield
    except:
        print('%s - Exception context: %s' % (datetime.strftime(datetime.now(), '%Y-%m-%d %H:%M:%S'), obj))
        raise


def retry_test(max_retries=0, wait_time_secs=0):
    def wrap(f):
        def wrapped_f(*args, **kwargs):
            retries = 0
            while True:
                try:
                    f(*args, **kwargs)
                    break
                except Exception:
                    if retries >= max_retries:
                        raise
                    else:
                        retries += 1
                        time.sleep(wait_time_secs)
                        print('%s - Retry #%d' % (datetime.strftime(datetime.now(), '%Y-%m-%d %H:%M:%S'), retries))

        return wrapped_f

    return wrap
