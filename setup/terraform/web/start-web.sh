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

PG_VERSION=15

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

function install_epel() {
  yum erase -y epel-release || true; rm -f /etc/yum.repos.r/epel* || true
  if [[ $(get_os_major_version) == "8" ]]; then
    if [[ $(get_os_type) == "CENTOS" ]]; then
      patch_yum_repos_for_centos
      dnf config-manager --set-enabled powertools
      dnf -y install epel-release epel-next-release
    else
      dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    fi
  else
    patch_yum_repos_for_centos
    yum_install epel-release
  fi
  yum clean all
  rm -rf /var/cache/yum/
  # Load and accept GPG keys
  yum makecache -y || true
  yum repolist
}

function install_pg_repo() {
  if [[ $(rpm -qa | grep pgdg-redhat-repo- | wc -l) -eq 0 ]]; then
    if [[ $(get_os_major_version) -eq 7 ]]; then
      yum_install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    else
      # Ref: https://www.postgresql.org/download/linux/redhat/
      sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
      sudo dnf -qy module disable postgresql
    fi
  fi
}

function install_python() {
  if [[ $(get_os_major_version) == "7" ]]; then
    yum_install centos-release-scl
    patch_yum_repos_for_centos
    yum_install rh-python38 rh-python38-python-devel
    alternatives --install /usr/bin/python3 workshop-py3-38 /opt/rh/rh-python38/root/usr/bin/python3.8 99999999
    /opt/rh/rh-python38/root/usr/bin/pip3 install --quiet --upgrade pip virtualenv
    MANPATH= source /opt/rh/rh-python38/enable
    cat /opt/rh/rh-python38/enable >> /etc/profile
  else
    yum_install python38 python38-devel
    /usr/bin/pip3.8 install --quiet --upgrade pip virtualenv
  fi
}

function patch_yum_repos_for_centos() {
  # In July 2024 Centos 7 reached EoL and the repo was moved to the CentOS Vault.
  # The mirrorlist.centos.org host was also decommissioned.
  # The commands below update YUM repo file accordingly, if needed
  local files=$(find /etc/yum.repos.d/ -name "*.repo" | grep -v epel)
  if [[ $(get_os_type) == "CENTOS" ]]; then
    sed -i 's/mirror.centos.org/vault.centos.org/g' $files
    sed -i 's/^#.*baseurl=http/baseurl=http/g' $files
    sed -i 's/^mirrorlist=http/#mirrorlist=http/g' $files
    sed -i 's/metalink=/#metalink=/' $files
  fi
}

function get_os_major_version() {
  grep "^VERSION=" /etc/os-release 2> /dev/null | sed 's/VERSION=["'\'']//g' | grep -o "^."
}

function get_os_type() {
  if grep "^NAME=.*Red Hat Enterprise Linux" /etc/os-release > /dev/null 2>&1; then
    echo "RHEL"
  elif grep -i "^NAME=.*centos" /etc/os-release > /dev/null 2>&1; then
    echo "CENTOS"
  else
    echo "UNKNOWN"
  fi
}

log_status "Disabling SElinux"
sudo setenforce 0
sudo sed -i.bak 's/^ *SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sudo sestatus

log_status "Disabling IPv6"
cat <<EOF | sudo tee -a /etc/sysctl.conf
vm.swappiness = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo sysctl -p

if [[ $(get_os_type) == "RHEL" ]]; then
  log_status "Disable RHEL Subscription Manager"
  sudo sed -i.bak 's/^ *enabled=.*/enabled=0/' /etc/yum/pluginconf.d/subscription-manager.conf
fi

log_status "Installing EPEL and PG repositories and Python"
sudo bash -c "$(for func in yum_install install_epel install_pg_repo install_python patch_yum_repos_for_centos get_os_type get_os_major_version; do declare -f "$func"; done); set -x; set -e; set -u; set -o pipefail; install_epel; install_pg_repo; install_python"
# Since the installation above is done in a sub-shell, ensure Python's setting are effective
hash -r
[[ -f /opt/rh/rh-python38/enable ]] && MANPATH= source /opt/rh/rh-python38/enable || true

log_status "Installing needed tools"
yum_install supervisor nginx postgresql${PG_VERSION}-server postgresql${PG_VERSION} postgresql${PG_VERSION}-contrib figlet cowsay
# Supervisor's install can mess with Python paths, so we fix it if needed
if [[ -f /usr/bin/python3.8 ]]; then
  sudo alternatives --set python3 /usr/bin/python3.8
fi

log_status "Configuring PostgreSQL"
sudo bash -c 'echo '\''LC_ALL="en_US.UTF-8"'\'' >> /etc/locale.conf'
sudo /usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup initdb
sudo sed -i '/host *all *all *127.0.0.1\/32 *ident/ d' /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf
sudo bash -c "cat >> /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf <<EOF
host all all 127.0.0.1/32 md5
host all all ${PRIVATE_IP}/32 md5
host all all 127.0.0.1/32 ident
EOF
"
sudo sed -i '/^[ #]*\(listen_addresses\|max_connections\|shared_buffers\|wal_buffers\|checkpoint_segments\|checkpoint_completion_target\) *=.*/ d' /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf
sudo bash -c "cat >> /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf <<EOF
listen_addresses = '*'
max_connections = 2000
shared_buffers = 256MB
wal_buffers = 8MB
checkpoint_completion_target = 0.9
EOF
"

log_status "Starting PostgreSQL"
sudo systemctl enable postgresql-${PG_VERSION}
sudo systemctl start postgresql-${PG_VERSION}

log_status "Creating databases"
sudo -u postgres psql <<EOF
create role ${DB_USER} login password '${DB_PWD}';
create database ${DB_NAME} owner ${DB_USER} encoding 'UTF8';
EOF

log_status "Preparing virtualenv"
set +e; python -V; type python; pip -V; type pip; set -e
python3 -m venv $BASE_DIR/env
source $BASE_DIR/env/bin/activate
set +e; python -V; type python; pip -V; type pip; set -e
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
figlet -f small -w 300  "Web server deployed successfully"'!' | /usr/bin/cowsay -n -f "$(find /usr/share/cowsay -type f -name "*.cow" | grep "\.cow" | sed 's#.*/##;s/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
echo "Completed successfully: WEB"
