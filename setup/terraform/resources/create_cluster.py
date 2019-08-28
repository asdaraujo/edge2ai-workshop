from __future__ import print_function
from cm_client.rest import ApiException
from collections import namedtuple
from datetime import datetime
import cm_client
import json
import sys
import time
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
        for child in cmd.children.items:
            print_cmd(child, indent+2)

def wait(cmd, timeout=None):
    SYNCHRONOUS_COMMAND_ID = -1
    if cmd.id == SYNCHRONOUS_COMMAND_ID:
        return cmd

    SLEEP_SECS = 5
    if timeout is None:
        deadline = None
    else:
        deadline = time.time() + timeout

    try:
        cmd_api_instance = cm_client.CommandsResourceApi(api_client)
        while True:
            cmd = cmd_api_instance.read_command(long(cmd.id))
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

HOST = sys.argv[1]
TEMPLATE = sys.argv[2]
KEY_FILE = sys.argv[3]
CM_REPO_URL = sys.argv[4]

cm_client.configuration.username = 'admin'
cm_client.configuration.password = 'admin'
api_client = cm_client.ApiClient("http://localhost:7180/api/v32")

cm_api = cm_client.ClouderaManagerResourceApi(api_client)

# accept trial licence
cm_api.begin_trial()

# Install CM Agent on host
with open (KEY_FILE, "r") as f:
    key = f.read()


instargs = cm_client.ApiHostInstallArguments(host_names=[HOST], 
                                             user_name='root', 
                                             private_key=key, 
                                             cm_repo_url=CM_REPO_URL,
                                             java_install_strategy='NONE', 
                                             ssh_port=22, 
                                             passphrase='')

cmd = cm_api.host_install_command(body=instargs)
cmd = wait(cmd)
if not cmd.success:
    raise RuntimeError('Failed to add host to the cluster')

# create MGMT/CMS
mgmt_api = cm_client.MgmtServiceResourceApi(api_client)
api_service = cm_client.ApiService()

api_service.roles = [cm_client.ApiRole(type='SERVICEMONITOR'), 
    cm_client.ApiRole(type='HOSTMONITOR'), 
    cm_client.ApiRole(type='EVENTSERVER'),  
    cm_client.ApiRole(type='ALERTPUBLISHER')]

mgmt_api.auto_assign_roles() # needed?
mgmt_api.auto_configure()    # needed?
mgmt_api.setup_cms(body=api_service)
cmd = mgmt_api.start_command()
cmd = wait(cmd)
if not cmd.success:
    raise RuntimeError('Failed to start Management Services')

# Update host-level parameter required by SMM
all_hosts_api = cm_client.AllHostsResourceApi(api_client)
all_hosts_api.update_config(message='Updating parameter for SMM',
                            body=cm_client.ApiConfigList([
                                     cm_client.ApiConfig(name='host_agent_safety_valve',
                                                         value='kafka_broker_topic_partition_metrics_for_smm_enabled=true')
                                 ])
                           )

# create the cluster using the template
with open(TEMPLATE) as f:
    json_str = f.read()

Response = namedtuple("Response", "data")
dst_cluster_template=api_client.deserialize(response=Response(json_str),response_type=cm_client.ApiClusterTemplate)
cmd = cm_api.import_cluster_template(add_repositories=True, body=dst_cluster_template)
cmd = wait(cmd)
if not cmd.success:
    raise RuntimeError('Failed to deploy cluster template')
