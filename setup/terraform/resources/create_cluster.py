#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Cluster creation controls for Cloudera Manager submission"""

from cm_client.rest import ApiException
from collections import namedtuple
from datetime import datetime
from optparse import OptionParser
import cm_client
import os
import re
import requests
import socket
import time
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

OPT_PARSER = None
HEADER_COLORS = ['BLUE', 'DARKBLUE', 'GREEN', 'TEAL', 'PURPLE', 'PINK', 'GRAY', 'RED', 'YELLOW', 'BROWN']
LOG_FILE_PATH = '/var/log/cloudera-scm-server/cloudera-scm-server.log'


def print_cmd(cmd, indent=0):
    cmd_id = int(cmd.id)
    cmd_name = cmd.name
    cmd_status = 'Running' if cmd.active else 'Succeeded' if cmd.success else 'FAILED'
    cmd_msg = (' (' + cmd.result_message + ')') if cmd.result_message else ''
    indent_str = ' ' * (indent - 2) + ' +- ' if indent > 1 else ''
    details = [
        'Cluster: ' + (
            cmd.cluster_ref.display_name if cmd.cluster_ref.display_name else cmd.cluster_ref.cluster_name) if cmd.cluster_ref else '',
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
            print_cmd(child, indent + 2)


def _get_parser():
    global OPT_PARSER
    if OPT_PARSER is None:
        OPT_PARSER = OptionParser(usage='%prog [options] <host>')
        OPT_PARSER.add_option('--setup-cm', action='store_true', dest='setup_cm',
                              help='Setup Cloudera Manager.')
        OPT_PARSER.add_option('--create-cluster', action='store_true', dest='create_cluster',
                              help='Create cluster.')
        # Create cluster options
        OPT_PARSER.add_option('--template', action='store', dest='template',
                              help='Cluster template file.')
        # CM setup options
        OPT_PARSER.add_option('--key-file', action='store', dest='key_file',
                              help='SSH key file.')
        OPT_PARSER.add_option('--cm-repo-url', action='store', dest='cm_repo_url',
                              help='CM repo URL.')
        OPT_PARSER.add_option('--use-kerberos', action='store_true', dest='use_kerberos',
                              help='Enable Kerberos for the cluster.')
        OPT_PARSER.add_option('--kerberos-type', action='store', dest='kerberos_type',
                              help='KDC type (MIT or IPA).', default='MIT')
        OPT_PARSER.add_option('--ipa-host', action='store', dest='ipa_host',
                              help='IPA server hostname.', type='string', default=None)
        OPT_PARSER.add_option('--use-tls', action='store_true', dest='use_tls',
                              help='Enable TLS for the cluster.')
        OPT_PARSER.add_option('--tls-ca-cert', action='store', dest='tls_ca_cert', default=None,
                              help='TLS truststore.')
    return OPT_PARSER


def parse_args():
    return _get_parser().parse_args()


def to_int(x):
    try:
        return (int(x))
    except:
        return 999


def cm_major_version():
    return int(os.environ.get('CM_MAJOR_VERSION', '7'))


def cm_version():
    cm_version = os.environ.get('CM_VERSION', '999.999.999')
    return [to_int(x) for x in re.split('[-.]', cm_version)]


def the_pwd():
    return os.environ['THE_PWD']


def cluster_id():
    try:
        if 'CLUSTER_ID' in os.environ:
            return int(os.environ['CLUSTER_ID'])
    except:
        pass

    return 0


def local_hostname():
    return os.environ.get('LOCAL_HOSTNAME', 'edge2ai-1.local.dim')


def get_log_messages():
    if os.path.isfile(LOG_FILE_PATH):
        log_file = open(LOG_FILE_PATH, 'r')
        message = []
        for line in log_file:
            if not line.startswith(' ') and not line.startswith('\t'):
                if message:
                    yield ''.join(message).rstrip()
                    message = []
            message.append(line)

        if message:
            yield ''.join(message).rstrip()
            message = []


def print_errors(tail_size):
    messages = [msg for msg in get_log_messages() if
                re.match(r'.*(ERROR|Caused by|Exception)', msg) and not re.match(r'.*(PeriodicJmx)', msg)]
    for msg in messages[-tail_size:]:
        print(msg)


class ClusterCreator:
    def __init__(self, host, krb_princ='scm/admin@WORKSHOP.COM', tls_ca_cert=None):
        self.host = host
        self.krb_princ = krb_princ

        self._api_client = None
        self._cm_api = None
        self._mgmt_api = None
        self._hosts_api = None
        self._all_hosts_api = None
        self._cluster_api = None

        cm_client.configuration.username = 'admin'
        cm_client.configuration.password = the_pwd()
        cm_client.configuration.ssl_ca_cert = tls_ca_cert

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

    def _get_api_version(self):
        resp = requests.get("http://" + self.host + ":7180/api/version", verify=False, auth=('admin', the_pwd()))
        if resp.status_code == 200 and resp.text:
            return resp.text
        return requests.get("https://" + self.host + ":7183/api/version", verify=False, auth=('admin', the_pwd())).text

    @property
    def api_client(self):
        if self._api_client is None:
            if cm_client.configuration.ssl_ca_cert:
                api_url = "https://" + self.host + ":7183/api"
            else:
                api_url = "http://" + self.host + ":7180/api"
            self._api_client = cm_client.ApiClient(api_url + '/' + self._get_api_version())
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
    def hosts_api(self):
        if self._hosts_api is None:
            self._hosts_api = cm_client.HostsResourceApi(self.api_client)
        return self._hosts_api

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

    def setup_cm(self, key_file, cm_repo_url, use_kerberos, use_tls, kerberos_type, ipa_host):

        # Accept trial licence
        try:
            self.cm_api.begin_trial()
        except ApiException as exc:
            if exc.status == 400 and 'Trial has been used' in exc.body:
                pass  # This can be ignored
            else:
                raise

        # Install CM Agent on host
        with open(key_file, "r") as f:
            key = f.read()

        if self.host not in [h.hostname for h in self.hosts_api.read_hosts().items]:
            instargs = cm_client.ApiHostInstallArguments(host_names=[self.host],
                                                         user_name='root',
                                                         private_key=key,
                                                         cm_repo_url=cm_repo_url,
                                                         java_install_strategy='NONE',
                                                         ssh_port=22,
                                                         passphrase='')

            cmd = self.cm_api.host_install_command(body=instargs)
            cmd = self.wait(cmd)
            if not cmd.success:
                raise RuntimeError('Failed to add host to the cluster')

        # Create MGMT/CMS
        try:
            self.mgmt_api.read_service()
            print("Cloudera Management Services already installed")
            cms_exists = True
        except cm_client.rest.ApiException as e:
            cms_exists = False

        if not cms_exists:
            print("Installing Cloudera Management Services")
            api_service = cm_client.ApiService()
            api_service.roles = [cm_client.ApiRole(type='SERVICEMONITOR'),
                                 cm_client.ApiRole(type='HOSTMONITOR'),
                                 cm_client.ApiRole(type='EVENTSERVER'),
                                 cm_client.ApiRole(type='ALERTPUBLISHER')]
            self.mgmt_api.setup_cms(body=api_service)
            cmd = self.mgmt_api.start_command()
            cmd = self.wait(cmd)
            if not cmd.success:
                raise RuntimeError('Failed to start Management Services')

        # Update cluster banner
        c_id = cluster_id()
        banner = 'Cluster ID: {}, Host: {}'.format(c_id, socket.gethostname())
        header_color = HEADER_COLORS[c_id % len(HEADER_COLORS)]
        self.cm_api.update_config(
            message='Customizing CM header and banner',
            body=cm_client.ApiConfigList([
                cm_client.ApiConfig(name='CUSTOM_BANNER_HTML', value=banner),
                cm_client.ApiConfig(name='CUSTOM_HEADER_COLOR', value=header_color),
            ])
        )

        # Update host-level parameter required by SMM
        self.all_hosts_api.update_config(
            message='Updating parameter for SMM',
            body=cm_client.ApiConfigList([
                cm_client.ApiConfig(
                    name='host_agent_safety_valve',
                    value='kafka_broker_topic_partition_metrics_for_smm_enabled=true'
                )
            ])
        )

        # Enable kerberos
        if use_kerberos:
            self._enable_kerberos(kerberos_type, ipa_host)

        # Enable TLS
        if use_tls:
            self._enable_tls()

        # Restart Mgmt Services
        cmd = self.mgmt_api.restart_command()
        cmd = self.wait(cmd)

    def create_cluster(self, template):

        self._import_paywall_credentials()

        # Create the cluster using the template
        with open(template) as f:
            json_str = f.read()

        Response = namedtuple("Response", "data")
        dst_cluster_template = self.api_client.deserialize(response=Response(json_str),
                                                           response_type=cm_client.ApiClusterTemplate)
        cmd = self.cm_api.import_cluster_template(add_repositories=True, body=dst_cluster_template)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to deploy cluster template')

        # All parcel downloads should've already been done at this point, so we can safely remove the paywall credentials
        self._reset_paywall_credentials()

        # Restart Mgmt Services
        cmd = self.mgmt_api.restart_command()
        cmd = self.wait(cmd)

    def _enable_kerberos(self, kerberos_type, ipa_host):
        # Update Kerberos configuration
        config = [
            cm_client.ApiConfig(name='KRB_AUTH_ENABLE', value='true'),
            cm_client.ApiConfig(name='KRB_ENC_TYPES', value='aes256-cts rc4-hmac'),
            cm_client.ApiConfig(name='PUBLIC_CLOUD_STATUS', value='ON_PUBLIC_CLOUD'),
            cm_client.ApiConfig(name='SECURITY_REALM', value='WORKSHOP.COM'),
        ]
        if kerberos_type == 'MIT':
            config += [
                cm_client.ApiConfig(name='KDC_ADMIN_HOST', value=local_hostname()),
                cm_client.ApiConfig(name='KDC_HOST', value=local_hostname()),
                cm_client.ApiConfig(name='KDC_TYPE', value='MIT KDC'),
            ]
        else:
            config += [
                cm_client.ApiConfig(name='KDC_ADMIN_HOST', value=ipa_host),
                cm_client.ApiConfig(name='KDC_HOST', value=ipa_host),
                cm_client.ApiConfig(name='KDC_TYPE', value='Red Hat IPA'),
                cm_client.ApiConfig(name='AUTH_BACKEND_ORDER', value='LDAP_THEN_DB'),
                cm_client.ApiConfig(name='LDAP_BIND_DN',
                                    value='uid=ldap_bind_user,cn=users,cn=accounts,dc=workshop,dc=com'),
                cm_client.ApiConfig(name='LDAP_BIND_PW', value=the_pwd()),
                cm_client.ApiConfig(name='LDAP_GROUP_SEARCH_BASE', value='cn=groups,cn=accounts,dc=workshop,dc=com'),
                cm_client.ApiConfig(name='LDAP_GROUP_SEARCH_FILTER', value='(member={0})'),
                cm_client.ApiConfig(name='LDAP_TYPE', value='LDAP'),
                cm_client.ApiConfig(name='LDAP_URL', value='ldaps://' + ipa_host),
                cm_client.ApiConfig(name='LDAP_USER_SEARCH_BASE', value='cn=users,cn=accounts,dc=workshop,dc=com'),
                cm_client.ApiConfig(name='LDAP_USER_SEARCH_FILTER', value='(uid={0})'),
            ]
            if cm_version() < [7, 5, 3]:
                # These properties were removed in OPSAPS-61384 (CM 7.5.3)
                config += [
                    cm_client.ApiConfig(name='LDAP_BIND_DN_MONITORING',
                                        value='uid=ldap_bind_user,cn=users,cn=accounts,dc=workshop,dc=com'),
                    cm_client.ApiConfig(name='LDAP_BIND_PW_MONITORING', value=the_pwd()),
                ]
        self.cm_api.update_config(message='Updating Kerberos config', body=cm_client.ApiConfigList(config))

        # Import Kerberos credentials
        cmd = self.cm_api.import_admin_credentials(password=the_pwd(), username=self.krb_princ)
        cmd = self.wait(cmd)
        if not cmd.success:
            raise RuntimeError('Failed to import admin credentials')

    def _enable_tls(self):
        # Update TLS configuration
        self.cm_api.update_config(
            message='Updating TLS config',
            body=cm_client.ApiConfigList([
                cm_client.ApiConfig(name='AGENT_TLS', value='true'),
                cm_client.ApiConfig(name='KEYSTORE_PASSWORD', value=the_pwd()),
                cm_client.ApiConfig(name='KEYSTORE_PATH', value='/opt/cloudera/security/jks/keystore.jks'),
                cm_client.ApiConfig(name='NEED_AGENT_VALIDATION', value='true'),
                cm_client.ApiConfig(name='SCM_PROXY_TIMEOUT', value='30000'),
                cm_client.ApiConfig(name='TRUSTSTORE_PASSWORD', value=the_pwd()),
                cm_client.ApiConfig(name='TRUSTSTORE_PATH', value='/opt/cloudera/security/jks/truststore.jks'),
                cm_client.ApiConfig(name='WEB_TLS', value='true'),
            ]))
        self.mgmt_api.update_service_config(
            message='Updating TLS config for Mgmt Services',
            body=cm_client.ApiServiceConfig([
                cm_client.ApiConfig(name='ssl_client_truststore_location',
                                    value='/opt/cloudera/security/jks/truststore.jks'),
                cm_client.ApiConfig(name='ssl_client_truststore_password', value=the_pwd()),
            ]))


if __name__ == '__main__':
    (options, args) = parse_args()

    if len(args) != 1:
        _get_parser().print_help()
        exit(1)
    HOST = args[0]

    if options.kerberos_type == 'IPA':
        krb_princ = 'admin@WORKSHOP.COM'
    else:
        krb_princ = 'scm/admin@WORKSHOP.COM'
    CLUSTER_CREATOR = ClusterCreator(HOST, krb_princ=krb_princ, tls_ca_cert=options.tls_ca_cert)
    try:
        if (options.setup_cm):
            CLUSTER_CREATOR.setup_cm(options.key_file, options.cm_repo_url, options.use_kerberos, options.use_tls,
                                     options.kerberos_type, options.ipa_host)
        if (options.create_cluster):
            CLUSTER_CREATOR.create_cluster(options.template)
    except:
        print_errors(3)
        raise
