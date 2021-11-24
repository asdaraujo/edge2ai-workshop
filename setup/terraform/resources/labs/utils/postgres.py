#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from subprocess import Popen, PIPE
from . import *


def execute_sql(cmd, db_name, username, password):
    cmd_line = 'PGPASSWORD={pwd} psql --host {hostname} --port 5432 --username {usr} {db}'.format(
        usr=username, pwd=password, db=db_name, hostname=get_hostname())
    proc = Popen(cmd_line, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE)
    stdout, stderr = proc.communicate(cmd.encode('utf-8'))
    return proc.returncode, stdout, stderr
