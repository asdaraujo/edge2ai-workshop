#!/bin/bash
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
BASE_DIR=$(cd $(dirname $0); pwd -L)

DB_HOST=localhost
DB_NAME=workshop
DB_USER=workshop
DB_PWD=supersecret1

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

# Disable SElinux
sudo setenforce 0
sudo sed -i.bak 's/^ *SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sudo sestatus

## MariaDB 10.1 repo file
sudo bash -c "
cat > /etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
"

# Install stuff
yum_install epel-release
yum_install python36-pip python36 supervisor nginx MariaDB-server MariaDB-client

# Start MariaDB
sudo bash -c "
cat > /etc/my.cnf <<EOF
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
transaction-isolation = READ-COMMITTED
symbolic-links = 0
key_buffer = 16M
key_buffer_size = 32M
max_allowed_packet = 32M
thread_stack = 256K
thread_cache_size = 64
query_cache_limit = 8M
query_cache_size = 64M
query_cache_type = 1
max_connections = 550
#log_bin=/var/lib/mysql/mysql_binary_log
server_id=1
binlog_format = mixed
read_buffer_size = 2M
read_rnd_buffer_size = 16M
sort_buffer_size = 8M
join_buffer_size = 8M
innodb_file_per_table = 1
innodb_flush_log_at_trx_commit  = 2
innodb_log_buffer_size = 64M
innodb_buffer_pool_size = 4G
innodb_thread_concurrency = 8
innodb_flush_method = O_DIRECT
innodb_log_file_size = 512M

[mysqld_safe]
etc/my.cnf.d/mariadb.pidg
log-error=/var/log/mariadb/mariadb.log
pid-file=/var/run/mariadb/mariadb.pid

!includedir /etc/my.cnf.d
EOF
"
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Create databases
mysql -u root <<EOF
create database ${DB_NAME} character set utf8 collate utf8_bin;
create user '${DB_USER}'@'${DB_HOST}' identified by '${DB_PWD}';
grant all privileges on ${DB_NAME}.* to '${DB_USER}'@'${DB_HOST}';
flush privileges;
EOF

# Secure MariaDB
mysql -u root <<EOF
UPDATE mysql.user SET Password=PASSWORD('supersecret1') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# Prepare virtualenv
python3 -m venv $BASE_DIR/env
source $BASE_DIR/env/bin/activate
pip install --quiet --upgrade pip virtualenv
pip install --progress-bar off -r $BASE_DIR/requirements.txt
pip install --progress-bar off gunicorn pymysql

# Setup env
cat > $BASE_DIR/.env <<EOF
SECRET_KEY=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
DATABASE_URL=mysql+pymysql://workshop:${DB_PWD}@${DB_HOST}:3306/${DB_NAME}
EOF

# Initialize database tables
rm -rf $BASE_DIR/app.db $BASE_DIR/migrations
flask db init
flask db migrate -m "initial tables"
flask db upgrade

# Setup supervisord
sudo bash -c "
cat > /etc/supervisord.d/workshop.ini <<EOF
[program:workshop]
command=$BASE_DIR/env/bin/gunicorn -b localhost:8000 -w 4 workshop:app
directory=$BASE_DIR
user=$(whoami)
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
EOF
"

# Start supervisord
sudo systemctl enable supervisord
sudo systemctl start supervisord
sudo /usr/bin/supervisorctl reload

# Create nginx certs
sudo -u nginx mkdir -p /var/lib/nginx/certs
sudo -u nginx chown nginx:nginx /var/lib/nginx/certs
sudo -u nginx chmod 700 /var/lib/nginx/certs
sudo -u nginx openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -keyout /var/lib/nginx/certs/key.pem \
  -out /var/lib/nginx/certs/cert.pem -subj "/C=US/ST=California/L=San Francisco/O=Cloudera/OU=DIM/CN=$(hostname -f)"

# Configure nginx
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
        proxy_pass http://localhost:8000/;
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
        proxy_pass http://localhost:8000;
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

# Relax homedir permissions so that nginx can access static files
chmod 755 $HOME

# Start nginx
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl reload nginx
