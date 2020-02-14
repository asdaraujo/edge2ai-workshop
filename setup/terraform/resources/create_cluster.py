#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Cluster creation controls for Cloudera Manager submission"""

from cm_client.rest import ApiException
from collections import namedtuple
from datetime import datetime
from optparse import OptionParser
import cm_client
import json
import os
import sys
import time
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

OPT_PARSER = None

def print_cmd(cmd, indent=0):
    cmd_id = int(cmd.id)
    cmd_name = cmd.name
    cmd_status = 'Running' if cmd.active else 'Succeeded' if cmd.success else 'FAILED'
    cmd_msg = (' (' + cmd.result_message + ')') if cmd.result_message else ''
    indent_str = ' '*(indent-2) + ' +- ' if indent > 1 else ''
    details = [
        'Cluster: ' + cmd.cluster_ref.display_name if cmd.cluster_ref else '',
        'Service: ' + cmd.service_ref.service_name if cmd.service_ref else '',
        'Role: ' + cmd.role_ref.role_name if cmd.role_ref else '',
        'Host: ' + cmd.host_ref.hostname if cmd.host_ref else '',
    ]
    details = [i for i in details if i]
    if details:
        details = '(' + ', '.join(details) + ')'
    else:
        details = ''
    msg = '%sCmd ID: %s, Name: %s, Status: %s%s %s' % (indent_str, cmd_id, cmd_name, cmd_status, cmd_msg, details)
    print(msg)
    if cmd.children and cmd.children.items:
        for child in sorted(cmd.children.items, key=lambda x: x.id):
            print_cmd(child, indent+2)

def _get_parser():
    global OPT_PARSER
    if OPT_PARSER is None:
        OPT_PARSER = OptionParser(usage='%prog [options] <host> <template> <key_file> <cm_repo_url>')
        OPT_PARSER.add_option('--use-kerberos', action='store_true', dest='use_kerberos',
                              help='Enable Kerberos for the cluster.')
    return OPT_PARSER

def parse_args():
    return _get_parser().parse_args()

def cm_major_version():
    return int(os.environ.get('CM_MAJOR_VERSION', '7'))

class ClusterCreator:
    def __init__(self, host, template, key_file, cm_repo_url, use_kerberos,
                 krb_princ='scm/admin@WORKSHOP.COM', krb_pass='supersecret1'):
        self.host = host
        self.template = template
        self.key_file = key_file
        self.cm_repo_url = cm_repo_url
        self.use_kerberos = use_kerberos
        self.krb_princ = krb_princ
        self.krb_pass = krb_pass
        
        self._api_client = None
        self._cm_api = None
        self._mgmt_api = None
        self._all_hosts_api = None
        self._cluster_api = None

        cm_client.configuration.username = 'admin'
        cm_client.configuration.password = 'admin'

    def _import_paywall_credentials(self):
        if cm_major_version() >= 7:
            configs = []
            if 'REMOTE_REPO_USR' in os.environ and os.environ['REMOTE_REPO_USR']:
                paywall_usr = os.environ['REMOTE_REPO_USR']
                configs.append(cm_client.ApiConfig(name='REMOTE_REPO_OVERRIDE_USER', value=paywall_usr))
            if 'REMOTE_REPO_PWD' in os.environ and os.environ['REMOTE_REPO_PWD']:
                paywall_pwd = os.environ['REMOTE_REPO_PWD']
                configs.append(cm_client.ApiConfig(name='REMOTE_REPO_OVERRIDE_PASSWORD', value=paywall_pwd))
            try:
                if configs:
                    self.cm_api.update_config(message='Importing paywall credentials',
                                              body=cm_client.ApiConfigList(configs))
            except ApiException:
                pass

    def _reset_paywall_credentials(self):
        if cm_major_version() >= 7:
            try:
                self.cm_api.update_config(message='Importing paywall credentials',
                                          body=cm_client.ApiConfigList([
                                                   cm_client.ApiConfig(name='REMOTE_REPO_OVERRIDE_USER', value=None),
                                                   cm_client.ApiConfig(name='REMOTE_REPO_OVERRIDE_PASSWORD', value=None)
                                               ])
                                         )
            except ApiException:
                pass

    @property
    def api_client(self):
        if self._api_client is None:
            self._api_client = cm_client.ApiClient("http://localhost:7180/api/v32")
        return self._api_client

    @property
    def cm_api(self):
        if self._cm_api is None:
            self._cm_api = cm_client.ClouderaManagerResourceApi(self.api_client)
        return self._cm_api

    @property
    def mgmt_api(self):
        if self._mgmt_api is None:
            self._mgmt_api = cm_client.MgmtServiceResourceApi(self.api_client)
        return self._mgmt_api

    @property
    def all_hosts_api(self):
        if self._all_hosts_api is None:
            self._all_hosts_api = cm_client.AllHostsResourceApi(self.api_client)
        return self._all_hosts_api

    @property
    def cluster_api(self):
        if self._cluster_api is None:
            self._cluster_api = cm_client.ClustersResourceApi(self.api_client)
        return self._cluster_api

    def wait(self, cmd, timeout=None):
        SYNCHRONOUS_COMMAND_ID = -1
        if cmd.id == SYNCHRONOUS_COMMAND_ID:
            return cmd
    
        SLEEP_SECS = 5
        if timeout is None:
            deadline = None
        else:
            deadline = time.time() + timeout
    
        try:
            cmd_api_instance = cm_client.CommandsResourceApi(self.api_client)
            while True:
                cmd = cmd_api_instance.read_command(int(cmd.id))
                print(datetime.strftime(datetime.now(), '%c'))
                print_cmd(cmd)
                if not cmd.active:
                    return cmd
    
                if deadline is not None:
                    now = time.time()
                    if deadline < now:
                        return cmd
                    else:
                        time.sleep(min(SLEEP_SECS, deadline - now))
                else:
                    time.sleep(SLEEP_SECS)
        except ApiException as e:
            print("Exception when calling ClouderaManagerResourceApi->import_cluster_template: %s\n" % e)

    def create_cluster(self):

        # accept trial licence
        try:
            self.cm_api.begin_trial()
        except ApiException as exc:
            if exc.status == 400 and 'Trial has been used' in exc.body:
                pass # This can be ignored
            else:
                raise
        
        # Install CM Agent on host
        with open (self.key_file, "r") as f:
            key = f.read()
        
        self._import_paywall_credentials()
        instargs = cm_client.ApiHostInstallArguments(host_names=[self.host], 
                                                     user_name='root', 
                                                     private_key=key, 
                                                     cm_repo_url=self.cm_repo_url,
                                                     java_install_strategy='NONE', 
                                                     ssh_port=22, 
                                                     passphrase='')
        
        cmd = self.cm_api.host_install_command(body=instargs)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to add host to the cluster')
        
        # create MGMT/CMS
        api_service = cm_client.ApiService()
        api_service.roles = [cm_client.ApiRole(type='SERVICEMONITOR'), 
            cm_client.ApiRole(type='HOSTMONITOR'), 
            cm_client.ApiRole(type='EVENTSERVER'),  
            cm_client.ApiRole(type='ALERTPUBLISHER')]
        
        self.mgmt_api.auto_assign_roles()  # needed?
        self.mgmt_api.auto_configure()    # needed?
        self.mgmt_api.setup_cms(body=api_service)
        cmd = self.mgmt_api.start_command()
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to start Management Services')
        
        # Update host-level parameter required by SMM
        self.all_hosts_api.update_config(message='Updating parameter for SMM',
                                         body=cm_client.ApiConfigList([
                                                  cm_client.ApiConfig(name='host_agent_safety_valve',
                                                                      value='kafka_broker_topic_partition_metrics_for_smm_enabled=true')
                                              ])
                                        )
        
        # create the cluster using the template
        with open(self.template) as f:
            json_str = f.read()
        
        Response = namedtuple("Response", "data")
        dst_cluster_template = self.api_client.deserialize(response=Response(json_str),response_type=cm_client.ApiClusterTemplate)
        cmd = self.cm_api.import_cluster_template(add_repositories=True, body=dst_cluster_template)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to deploy cluster template')

        # All parcel downloads should've already been done at this point, so we can safely remove the paywall credentials
        self._reset_paywall_credentials()

        if self.use_kerberos:
            self._enable_kerberos()
    
    def _enable_kerberos(self):
        # Update Kerberos configuration
        self.cm_api.update_config(message='Updating Kerberos config',
                                    body=cm_client.ApiConfigList([
                                             cm_client.ApiConfig(name='KDC_ADMIN_HOST', value='edge2ai-1.dim.local'),
                                             cm_client.ApiConfig(name='KDC_HOST', value='edge2ai-1.dim.local'),
                                             cm_client.ApiConfig(name='KDC_TYPE', value='MIT KDC'),
                                             cm_client.ApiConfig(name='KRB_ENC_TYPES', value='aes256-cts rc4-hmac'),
                                             cm_client.ApiConfig(name='PUBLIC_CLOUD_STATUS', value='ON_PUBLIC_CLOUD'),
                                             cm_client.ApiConfig(name='SECURITY_REALM', value='WORKSHOP.COM'),
                                         ]))
        
        
        # Import Kerberos credentials
        cmd = self.cm_api.import_admin_credentials(password=self.krb_pass, username=self.krb_princ)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to import admin credentials')
        
        # Configure Kerberos for the cluster
        cluster_name = 'OneNodeCluster'
        cmd = self.cluster_api.configure_for_kerberos(cluster_name, body=cm_client.ApiConfigureForKerberosArguments(datanode_transceiver_port=1004, datanode_web_port=1006))
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to configure services for Kerberos')
        
        # Stop cluster
        cmd = self.cluster_api.stop_command(cluster_name)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to stop cluster')
        
        # Stop Mgmt Services
        cmd = self.mgmt_api.stop_command()
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to stop management services')
        
        # Start Mgmt Services
        cmd = self.mgmt_api.start_command()
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to start management services')
        
        # Start cluster
        cmd = self.cluster_api.start_command(cluster_name)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to start cluster')
        
        # Deploy client config
        cmd = self.cluster_api.deploy_client_config(cluster_name)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to deploy client config')

if __name__ == '__main__':
    (options, args) = parse_args()

    if len(args) != 4:
        _get_parser().print_help()
        exit(1)

    CLUSTER_CREATOR = ClusterCreator(*args, use_kerberos=options.use_kerberos)
    CLUSTER_CREATOR.create_cluster()
    
