from eventador_core.dbadmin_utils import database_connect, get_real_dict_cursor, settings
import json
import socket
import subprocess
settings.DATABASE_PASSWORD = 'supersecret1'
conn = database_connect()
cur = get_real_dict_cursor(conn)
d_id = 'f7435c9ef876452c9abf66da9f603bc8'
cur.execute("SELECT hostmap FROM deployments WHERE deploymentid = %(d_id)s", {'d_id': d_id})
hm = cur.fetchone()
#jm_host, jm_port = subprocess.check_output('yarn app -list | grep "Flink session" | egrep -o "[^/:]*:[0-9]+" >&2', stderr=subprocess.STDOUT, shell=True, timeout=3, universal_newlines=True).split()[-1].split(':')
kafka_host = socket.gethostname()
#sqlio_host = socket.gethostname()
#snapper_host = socket.gethostname()
#hm['hostmap']['jobman0'][0]['host'] = jm_host
#hm['hostmap']['jobman0'][0]['port'] = jm_port
hm['hostmap']['kafka'][0]['host'] = kafka_host
#hm['hostmap']['sqlio']['endpoints'] = [{'host':sqlio_host}]
#hm['hostmap']['sqlio']['http_port'] = '18081'
#hm['hostmap']['snapper']['api_endpoint'] = snapper_host
#hm['hostmap']['snapper']['endpoints'] = [{'host':snapper_host}]
#hm['hostmap']['snapper']['http_port'] = '18082'
hostmap = hm['hostmap']
cur.execute("""UPDATE deployments SET hostmap = %(hostmap)s WHERE deploymentid = %(deploymentid)s""", {'hostmap': json.dumps(hostmap), 'deploymentid': d_id})
conn.commit()
#print("Hostmap successfully updated with values:\n    jobmanager host = {}\n    jobmanager port = {}\n    kafka host = {}\n    sqlio host = {}\n    snapper host = {}".format(jm_host, jm_port, kafka_host, sqlio_host, snapper_host))
print("Hostmap successfully updated with values:\n    kafka host = {}\n".format(kafka_host))