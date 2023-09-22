#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from subprocess import Popen, PIPE
from . import *


def _execute_cmd(cmd):
    proc = Popen(cmd, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError("Command failed to execute. Command: [{}]. Stdout: {}. Stderr: {}.".format(cmd,
                                                                                                      stdout, stderr))
    return proc.returncode, stdout, stderr


def _execute_srm_control(source, target, topic=None, group=None, remove=False, blacklist=False):
    assert (topic is None) ^ (group is None)
    if topic:
        operation = 'topics'
        subject = topic
    else:
        operation = 'groups'
        subject = group
    action = '{}{}'.format('remove' if remove else 'add', '-blacklist' if blacklist else '')
    cmd = 'SECURESTOREPASS={pwd} srm-control {operation}' \
          ' --source {source} --target {target} --{action} "{subject}"'.format(source=source, target=target,
                                                                               pwd=get_the_pwd(), subject=subject,
                                                                               operation=operation, action=action)
    return _execute_cmd(cmd)


def add_topic(source, target, topic, blacklist=False):
    return _execute_srm_control(source, target, topic=topic, blacklist=blacklist)
    # cmd = 'SECURESTOREPASS={pwd} srm-control topics --source {source} --target {target} --add "{topic}"'.format(
    #     source=source, target=target, pwd=get_the_pwd(), topic=topic)
    # return _execute_cmd(cmd)


def remove_topic(source, target, topic, blacklist=False):
    return _execute_srm_control(source, target, topic=topic, blacklist=blacklist, remove=True)
    # cmd = 'SECURESTOREPASS={pwd} srm-control topics --source {source} --target {target} --remove "{topic}"'.format(
    #     source=source, target=target, pwd=get_the_pwd(), topic=topic)
    # return _execute_cmd(cmd)


def add_group(source, target, group, blacklist=False):
    return _execute_srm_control(source, target, group=group, blacklist=blacklist)
    # cmd = 'SECURESTOREPASS={pwd} srm-control topics --source {source} --target {target} --add "{group}"'.format(
    #     source=source, target=target, pwd=get_the_pwd(), group=group)
    # return _execute_cmd(cmd)


def remove_group(source, target, group, blacklist=False):
    return _execute_srm_control(source, target, group=group, blacklist=blacklist, remove=True)
    # cmd = 'SECURESTOREPASS={pwd} srm-control topics --source {source} --target {target} --remove "{group}"'.format(
    #     source=source, target=target, pwd=get_the_pwd(), group=group)
    # return _execute_cmd(cmd)
