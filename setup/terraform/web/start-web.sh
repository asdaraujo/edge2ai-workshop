#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail
set -o xtrace
trap 'echo Setup return code: $?' 0
BASE_DIR=$(cd $(dirname $0); pwd -L)
cd $BASE_DIR

DB_HOST=$(hostname -f)
DB_NAME=workshop
DB_USER=workshop
DB_PWD=Supersecret1
PRIVATE_IP=$(hostname -I | awk '{print $1}')

function log_status() {
  local msg=$1
  echo "STATUS:$msg"
}

# Often yum connection to Cloudera repo fails and causes the instance create to fail.
# yum timeout and retries options don't see to help in this type of failure.
# We explicitly retry a few times to make sure the build continues when these timeouts happen.
function yum_install() {
  local packages=$@
  local retries=10
  while true; do
    set +e
    sudo yum install -d1 -y $packages
    RET=$?
    set -e
    if [ $RET == 0 ]; then
      break
    fi
    retries=$((retries - 1))
    if [ $retries -lt 0 ]; then
      echo 'YUM install failed!'
      break
    else
      echo 'Retrying YUM...'
    fi
  done
}

log_status "Disabling SElinux"
sudo setenforce 0
sudo sed -i.bak 's/^ *SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sudo sestatus

log_status "Installing what we need"
sudo yum erase -y epel-release || true
rm -f /etc/yum.repos.r/epel* || true
yum_install epel-release

# Installing Postgresql repo
if [[ $(rpm -qa | grep pgdg-redhat-repo- | wc -l) -eq 0 ]]; then
  yum_install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
fi

# The EPEL repo has intermittent refresh issues that cause errors like the one below.
# Switch to baseurl to avoid those issues when using the metalink option.
# Error: https://.../repomd.xml: [Errno -1] repomd.xml does not match metalink for epel
sudo sed -i 's/metalink=/#metalink=/;s/#*baseurl=/baseurl=/' /etc/yum.repos.d/epel*.repo

yum_install python36-pip python36 supervisor nginx postgresql10-server postgresql10 postgresql10-contrib figlet cowsay

log_status "Configuring PostgreSQL"
sudo bash -c 'echo '\''LC_ALL="en_US.UTF-8"'\'' >> /etc/locale.conf'
sudo /usr/pgsql-10/bin/postgresql-10-setup initdb
sudo sed -i '/host *all *all *127.0.0.1\/32 *ident/ d' /var/lib/pgsql/10/data/pg_hba.conf
sudo bash -c "cat >> /var/lib/pgsql/10/data/pg_hba.conf <<EOF
host all all 127.0.0.1/32 md5
host all all ${PRIVATE_IP}/32 md5
host all all 127.0.0.1/32 ident
EOF
"
sudo sed -i '/^[ #]*\(listen_addresses\|max_connections\|shared_buffers\|wal_buffers\|checkpoint_segments\|checkpoint_completion_target\) *=.*/ d' /var/lib/pgsql/10/data/postgresql.conf
sudo bash -c "cat >> /var/lib/pgsql/10/data/postgresql.conf <<EOF
listen_addresses = '*'
max_connections = 2000
shared_buffers = 256MB
wal_buffers = 8MB
checkpoint_completion_target = 0.9
EOF
"

log_status "Starting PostgreSQL"
sudo systemctl enable postgresql-10
sudo systemctl start postgresql-10

log_status "Creating databases"
sudo -u postgres psql <<EOF
create role ${DB_USER} login password '${DB_PWD}';
create database ${DB_NAME} owner ${DB_USER} encoding 'UTF8';
EOF

log_status "Preparing virtualenv"
python3 -m venv $BASE_DIR/env
source $BASE_DIR/env/bin/activate
pip install --quiet --upgrade pip virtualenv
pip install --progress-bar off -r $BASE_DIR/requirements.txt
pip install --progress-bar off gunicorn

log_status "Setting up environment"
cat > $BASE_DIR/.env <<EOF
SECRET_KEY=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
DATABASE_URL=postgresql+psycopg2://${DB_USER}:${DB_PWD}@${DB_HOST}:5432/${DB_NAME}
EOF

log_status "Initializing database tables"
rm -rf $BASE_DIR/app.db $BASE_DIR/migrations
pwd
flask db init
flask db migrate -m "initial tables"
flask db upgrade

log_status "Setting up supervisord"
mkdir -p $BASE_DIR/logs
sudo bash -c "
cat > /etc/supervisord.d/workshop.ini <<EOF
[program:workshop]
command=$BASE_DIR/env/bin/gunicorn -b 127.0.0.1:8000 -w 4 --error-logfile $BASE_DIR/logs/workshop.log --capture-output workshop:app
directory=$BASE_DIR
user=$(whoami)
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
EOF
"

log_status "Starting supervisord"
sudo systemctl enable supervisord
sudo systemctl start supervisord
sudo /usr/bin/supervisorctl reload

log_status "Creating nginx certificates"
sudo -u nginx mkdir -p /var/lib/nginx/certs
sudo -u nginx chown nginx:nginx /var/lib/nginx/certs
sudo -u nginx chmod 700 /var/lib/nginx/certs
sudo -u nginx openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -keyout /var/lib/nginx/certs/key.pem \
  -out /var/lib/nginx/certs/cert.pem -subj "/C=US/ST=California/L=San Francisco/O=Cloudera/OU=DIM/CN=$(hostname -f)"

log_status "Configuring nginx"
sudo bash -c '
cat > /etc/nginx/conf.d/workshop.conf <<'\''EOF'\''
server {
    # listen on port 80 (http)
    listen 80;
    server_name _;

# Optionally, uncomment the below and comment the location element below
# to allow only secure connections.
#    location / {
#        # redirect any requests to the same URL but on https
#        return 301 https://$host$request_uri;
#    }

    # write access and error logs to /var/log
    access_log /var/log/nginx/workshop_access.log;
    error_log /var/log/nginx/workshop_error.log;

    location / {
        # forward application requests to the gunicorn server
        proxy_pass http://127.0.0.1:8000/;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /static {
        # handle static files directly, without forwarding to the application
        alias '"$HOME"'/web/app/static;
        expires 30d;
    }
}

server {
    # listen on port 443 (https)
    listen 443 ssl;
    server_name workshop_secure;

    # location of the self-signed SSL certificate
    ssl_certificate /var/lib/nginx/certs/cert.pem;
    ssl_certificate_key /var/lib/nginx/certs/key.pem;

    # write access and error logs to /var/log
    access_log /var/log/nginx/secure_workshop_access.log;
    error_log /var/log/nginx/secure_workshop_error.log;

    location / {
        # forward application requests to the gunicorn server
        proxy_pass http://127.0.0.1:8000;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /static {
        # handle static files directly, without forwarding to the application
        alias '"$HOME"'/web/app/static;
        expires 30d;
    }
}
EOF
'

sudo bash -c '
cat > /etc/nginx/nginx.conf <<'\''EOF'\''
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
# Load dynamic modules. See /usr/share/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
http {
    log_format  main  '\''$remote_addr - $remote_user [$time_local] "$request" '\''
                      '\''$status $body_bytes_sent "$http_referer" '\''
                      '\''"$http_user_agent" "$http_x_forwarded_for"'\'';
    access_log  /var/log/nginx/access.log  main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    include /etc/nginx/conf.d/*.conf;
}
EOF
'

# Relaxing homedir permissions so that nginx can access static files
chmod 755 $HOME

log_status "Starting nginx"
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl reload nginx

log_status "Setup completed"
figlet -f small -w 300  "Web server deployed successfully"'!' | cowsay -n -f "$(ls -1 /usr/share/cowsay | grep "\.cow" | sed 's/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
echo "Completed successfully: WEB"
