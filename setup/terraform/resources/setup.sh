#! /bin/bash
set -o nounset
set -o errexit
set -o pipefail
set -o xtrace
trap 'echo Setup return code: $?' 0
BASE_DIR=$(cd "$(dirname $0)"; pwd -L)

if [ "$USER" != "root" ]; then
  echo "ERROR: This script ($0) must be executed by root"
  exit 1
fi

source $BASE_DIR/common.sh

log_status "Starting OneNodeCluster Setup Script"

#########  Set variables upfront

CLOUD_PROVIDER=${1:-aws}
SSH_USER=${2:-}
SSH_PWD=${3:-}
NAMESPACE=${4:-}
DOCKER_DEVICE=${5:-$(detect_docker_device)}
IPA_HOST=${6:-}
IPA_PRIVATE_IP=${7:-}
ECS_PUBLIC_DNS=${8:-}
ECS_PRIVATE_IP=${9:-}
export NAMESPACE DOCKER_DEVICE IPA_HOST

if [[ ! -z ${CLUSTER_ID:-} ]]; then
  PEER_CLUSTER_ID=$(( (CLUSTER_ID/2)*2 + (CLUSTER_ID+1)%2 ))
  PEER_PUBLIC_DNS=$(echo "${CLUSTERS_PUBLIC_DNS:-}" | awk -F, -v pos=$(( PEER_CLUSTER_ID + 1 )) '{print $pos}')
  PEER_PUBLIC_DNS=${PEER_PUBLIC_DNS:-$PUBLIC_DNS}
else
  CLUSTER_ID=0
  PEER_CLUSTER_ID=0
  PEER_PUBLIC_DNS=$PUBLIC_DNS
  LOCAL_HOSTNAME=edge2ai-0.dim.local
fi
export CLUSTER_ID PEER_CLUSTER_ID PEER_PUBLIC_DNS LOCAL_HOSTNAME

KEY_FILE=${BASE_DIR}/myRSAkey
TEMPLATE_FILE=$BASE_DIR/cluster_template.${NAMESPACE}.json
CM_REPO_FILE=/etc/yum.repos.d/cloudera-manager.repo
PREINSTALL_COMPLETED_FLAG=${BASE_DIR}/.preinstall.completed

get_public_ip
resolve_host_addresses
load_stack $NAMESPACE

# Save params
if [[ ! -f $BASE_DIR/.setup.params ]]; then
  echo "bash -x $0 '$CLOUD_PROVIDER' '$SSH_USER' '$SSH_PWD' '$NAMESPACE' '$DOCKER_DEVICE' '$IPA_HOST' '$IPA_PRIVATE_IP' '$ECS_PUBLIC_DNS' '$ECS_PRIVATE_IP'" > $BASE_DIR/.setup.params
fi


if [[ "$(is_tls_enabled)" == "yes" ]]; then
  touch $BASE_DIR/.enable-tls
fi
if [[ "$(is_kerberos_enabled)" == "yes" ]]; then
  touch $BASE_DIR/.enable-kerberos
fi
if [[ ${USE_IPA:-no} == "yes" ]]; then
  touch $BASE_DIR/.use-ipa
fi

if [ "$(get_remote_repo_username)" != "" -a "$(get_remote_repo_password)" != "" ]; then
  WGET_BASIC_AUTH="--user '$(get_remote_repo_username)' --password '$(get_remote_repo_password)'"
  CURL_BASIC_AUTH="-u '$(get_remote_repo_username):$(get_remote_repo_password)'"
else
  WGET_BASIC_AUTH=""
  CURL_BASIC_AUTH=""
fi

#########  Start Packer Installation

log_status "Testing if this is a pre-packed image by looking for existing Cloudera Manager repo"
if [[ ! -f $PREINSTALL_COMPLETED_FLAG ]]; then
  deploy_os_prereqs
  deploy_cluster_prereqs

  log_status "Installing CM repo"
  if [ "${CM_REPO_AS_TARBALL_URL:-}" == "" ]; then
    paywall_wget "$CM_REPO_FILE_URL" "$CM_REPO_FILE"
  else
    CM_DOWNLOADED_FILE=/var/www/html/.${CM_VERSION}-${CM_GBN:-}
    if [[ ! -f $CM_DOWNLOADED_FILE ]]; then
      sed -i.bak 's/^ *Listen  *.*/Listen 3333/' /etc/httpd/conf/httpd.conf
      systemctl start httpd

      CM_REPO_AS_TARBALL_FILE=/tmp/cm-repo-as-a-tarball.tar.gz
      paywall_wget "$CM_REPO_AS_TARBALL_URL" "$CM_REPO_AS_TARBALL_FILE"
      tar -C /var/www/html -xvf $CM_REPO_AS_TARBALL_FILE
      CM_REPO_ROOT_DIR=$((tar -tvf $CM_REPO_AS_TARBALL_FILE || true) | head -1 | awk '{print $NF}')
      if [[ $CM_MAJOR_VERSION == 5 ]]; then
        CM_REPO_ROOT_DIR=${CM_REPO_ROOT_DIR}/${CM_VERSION}
      fi
      rm -f $CM_REPO_AS_TARBALL_FILE

      KEYS_FILE=/var/www/html/${CM_REPO_ROOT_DIR%/}/allkeys.asc
      if [[ $CM_MAJOR_VERSION != 5 ]]; then
        # In some versions the allkeys.asc file is missing from the repo-as-tarball
        if [ ! -f "$KEYS_FILE" ]; then
          KEYS_URL="$(dirname "$(dirname "$CM_REPO_AS_TARBALL_URL")")/allkeys.asc"
          paywall_wget "$KEYS_URL" "$KEYS_FILE"
        fi
      fi

#      KEYS_FILE_SHA256=/var/www/html/${CM_REPO_ROOT_DIR%/}/allkeyssha256.asc
#      if [[ ! -f $KEYS_FILE_SHA256 ]]; then
#        # If allkeyssha256.asc is missing, link it to allkeys.asc
#        ln -s $KEYS_FILE $KEYS_FILE_SHA256
#      fi

      touch $CM_DOWNLOADED_FILE

      cat > $CM_REPO_FILE <<EOF
[cloudera-manager]
name = Cloudera Manager, Version
baseurl = http://localhost:3333/$CM_REPO_ROOT_DIR
gpgcheck = 0
EOF

      log_status "Cleaning repo cache"
      yum clean all
      rm -rf /var/cache/yum/
      # Force makecache to ensure GPG keys are loaded and accepted
      yum makecache -y || true
      yum repolist
    fi
  fi

  # Install Java after seting CM repo, in case we're sourcing Java from there
  log_status "Installing JDK packages"
  install_java

  log_status "Installing Postgresql repo"
  if [[ $(rpm -qa | grep pgdg-redhat-repo- | wc -l) -eq 0 ]]; then
    yum_install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
  fi

  log_status "Installing Cloudera Manager"
  # NOTE: must disable PG repos for this install due to some weird dependencies on psycopg2,
  # which maps to Python 3 on the PG repo, but to Python 2 on base.
  yum_install --disablerepo="pgdg*" cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server
  systemctl disable cloudera-scm-agent
  systemctl disable cloudera-scm-server

  log_status "Installing PostgreSQL"
  # PostgreSQL has a dependency on Java 8, so the install below will install the OpenJDK 8 package
  # We set the java alternatives manually here so that Java 8 doesn't take priority after the install
  CURRENT_JAVA=$(update-alternatives --display java | grep "link currently points to" | awk '{print $NF}')
  update-alternatives --set java "$CURRENT_JAVA"
  yum_install postgresql${PG_VERSION}-server postgresql${PG_VERSION} postgresql${PG_VERSION}-contrib postgresql-jdbc
  systemctl disable postgresql-${PG_VERSION}

  enable_py3
  pip install --quiet --upgrade pip
  # re-source after pip upgrade due to change in path of the pip executable
  enable_py3
  pip install --progress-bar off \
    cm-client==44.0.3 \
    impyla==0.17.0 \
    Jinja2==3.0.3 \
    kerberos==1.3.1 \
    nipyapi==0.17.1 \
    paho-mqtt==1.6.1 \
    psycopg2-binary==2.9.3 \
    pytest==6.2.5 \
    PyYAML==6.0 \
    requests==2.28.0 \
    requests-gssapi==1.2.3 \
    requests-kerberos==0.14.0 \
    thrift-sasl==0.4.3

  rm -f /usr/bin/python3 /usr/bin/pip3
  ln -s /opt/rh/rh-python38/root/bin/python3 /usr/bin/python3
  ln -s /opt/rh/rh-python38/root/bin/pip3 /usr/bin/pip3
  ln -s /opt/rh/rh-python38/root/usr/bin/python3.8 /usr/local/bin/python3.8

  log_status "Installing JDBC connector"
  cp /usr/share/java/postgresql-jdbc.jar /usr/share/java/postgresql-connector-java.jar
  chmod 644 /usr/share/java/postgresql-connector-java.jar

  log_status "Installing Maven"
  retry_if_needed 5 5 "curl '$MAVEN_BINARY_URL' > /tmp/apache-maven-bin.tar.gz"

  tar -C "$(get_homedir $SSH_USER)" -zxvf /tmp/apache-maven-bin.tar.gz
  rm -f /tmp/apache-maven-bin.tar.gz
  MAVEN_BIN=$(ls -d1tr "$(get_homedir $SSH_USER)"/apache-maven-*/bin | tail -1)
  echo "export PATH=\$PATH:$MAVEN_BIN" >> "$(get_homedir $SSH_USER)"/.bash_profile

  if [[ ${HAS_CEM:-} == "1" ]]; then
    log_status "Fetching and extracting CEM tarball to /opt/cloudera/cem"
    mkdir -p /opt/cloudera/cem
    if [ "${CEM_URL:-}" != "" ]; then
      CEM_TARBALL_NAME=$(basename ${CEM_URL%%\?*})
      CEM_TARBALL_PATH=/opt/cloudera/cem/${CEM_TARBALL_NAME}
      paywall_wget "$CEM_URL" "$CEM_TARBALL_PATH"
      tar -zxf $CEM_TARBALL_PATH -C /opt/cloudera/cem
      rm -f $CEM_TARBALL_PATH
    else
      for url in ${EFM_TARBALL_URL:-} ${MINIFI_TARBALL_URL:-} ${MINIFI_EXTRA_TARBALL_URL:-}; do
        TARBALL_NAME=$(basename ${url%%\?*})
        TARBALL_PATH=/opt/cloudera/cem/${TARBALL_NAME}
        paywall_wget "$url" "$TARBALL_PATH"
      done
    fi

    EFM_TARBALL=$(find /opt/cloudera/cem/ -name "efm-*-bin.tar.gz" | sort | tail -1)
    if [[ ${EFM_TARBALL:-} != "" ]]; then
      log_status "Installing and configuring EFM"
      EFM_BASE_NAME=$(basename $EFM_TARBALL | sed 's/-bin.tar.gz//')
      tar -zxf ${EFM_TARBALL} -C /opt/cloudera/cem
      rm -f /opt/cloudera/cem/efm /etc/init.d/efm
      ln -s /opt/cloudera/cem/${EFM_BASE_NAME} /opt/cloudera/cem/efm
      ln -s /opt/cloudera/cem/efm/bin/efm.sh /etc/init.d/efm
      sed -i '1s/.*/&\n# chkconfig: 2345 20 80\n# description: EFM is a Command \& Control service for managing MiNiFi deployments/' /opt/cloudera/cem/efm/bin/efm.sh
      chkconfig --add efm
      chown -R root:root /opt/cloudera/cem/${EFM_BASE_NAME}
      sed -i.bak 's#APP_EXT_LIB_DIR=.*#APP_EXT_LIB_DIR=/usr/share/java#' /opt/cloudera/cem/efm/conf/efm.conf
      # If Java is not 1.8, remove deprecated JVM option
      if [[ $(java -version 2>&1 | grep -c "\<1\.[786]") -eq 0 ]]; then
        sed -i.bak2 's/-XX:+UseParNewGC *//;s/UseConcMarkSweepGC/UseG1GC/' /opt/cloudera/cem/efm/conf/efm.conf
      fi
    fi

    MINIFI_TARBALL=$(find /opt/cloudera/cem/ -name "minifi-[0-9]*-bin.tar.gz" | sort | tail -1)
    if [[ ${MINIFI_TARBALL:-} != "" ]]; then
      log_status "Installing and configuring MiNiFi Java"
      MINIFI_BASE_NAME=$(basename $MINIFI_TARBALL | sed 's/-bin.tar.gz//')
      tar -zxf ${MINIFI_TARBALL} -C /opt/cloudera/cem
      rm -f /opt/cloudera/cem/minifi
      ln -s /opt/cloudera/cem/${MINIFI_BASE_NAME} /opt/cloudera/cem/minifi
      chown -R root:root /opt/cloudera/cem/${MINIFI_BASE_NAME}

      /opt/cloudera/cem/minifi/bin/minifi.sh install

      # Disabling services here for packer images - will reenable later
      systemctl disable minifi

      log_status "Downloading and installing MQTT Processor NAR file"
      retry_if_needed 5 5 "wget --progress=dot:giga https://repo1.maven.org/maven2/org/apache/nifi/nifi-mqtt-nar/1.8.0/nifi-mqtt-nar-1.8.0.nar -P /opt/cloudera/cem/minifi/lib"
      chown root:root /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
      chmod 660 /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
    fi

    if [[ $MINIFI_TARBALL == "" ]]; then
      CPP_MINIFI_TARBALL=$(find /opt/cloudera/cem/ -name "nifi-minifi-cpp-*-bin*.tar.gz" | sort | tail -1)
      if [[ ${CPP_MINIFI_TARBALL:-} != "" ]]; then
        log_status "Installing and configuring MiNiFi CPP"
        CPP_MINIFI_BASE_NAME=$(tar -tvf $CPP_MINIFI_TARBALL | head -1 | awk '{print $NF}' | sed 's#/##' || true)
        tar -zxf ${CPP_MINIFI_TARBALL} -C /opt/cloudera/cem
        rm -f /opt/cloudera/cem/minifi
        ln -s /opt/cloudera/cem/${CPP_MINIFI_BASE_NAME} /opt/cloudera/cem/minifi
        chown -R root:root /opt/cloudera/cem/${CPP_MINIFI_BASE_NAME}

        /opt/cloudera/cem/minifi/bin/minifi.sh install

        # Disabling services here for packer images - will reenable later
        systemctl disable minifi
      fi

      CPP_MINIFI_EXTRA_TARBALL=$(find /opt/cloudera/cem/ -name "nifi-minifi-cpp-*-extra-extensions*.tar.gz" | sort | tail -1)
      if [[ ${CPP_MINIFI_EXTRA_TARBALL:-} != "" ]]; then
        log_status "Installing and configuring Python extension for MiNiFi CPP"
        TMP_LIB_DIR=/tmp/minifi-libs.$$
        rm -rf $TMP_LIB_DIR
        mkdir -p $TMP_LIB_DIR
        tar -zxf ${CPP_MINIFI_EXTRA_TARBALL} -C $TMP_LIB_DIR
        cp -f $TMP_LIB_DIR/extra-extensions/{libminifi-script-extension.so,libminifi-python-script-extension.so} /opt/cloudera/cem/minifi/extensions
        rm -rf /opt/cloudera/cem/minifi/minifi-python/{examples,google,h2o}
        rm -rf $TMP_LIB_DIR

        # Ensure MiNiFi uses Python 3.8 instead of the default system version (3.6)
        if [[ -f /etc/rc.d/init.d/minifi ]]; then
          sed -i 's#export MINIFI_HOME#source /opt/rh/rh-python38/enable\nexport MINIFI_HOME#' /etc/rc.d/init.d/minifi
        else
          # TODO: In recent MiNiFi versions the minifi.sh install script no longer creates /etc/rc.d/init.d/minifi
          # TODO: Instead, it creates /usr/local/lib/systemd/system/minifi.service. We need another way to inject
          # TODO: Python 3.9 to the MiNiFi path.
          true
        fi
        systemctl daemon-reload
        yum_install --enablerepo=epel patchelf
        patchelf /opt/cloudera/cem/minifi/extensions/libminifi-python-script-extension.so --replace-needed libpython3.so libpython3.8.so

        # Install needed modules
        source /opt/rh/rh-python38/enable
        pip install numpy pandas scikit-learn==1.1.1 xgboost==1.6.2
      fi
    fi
  fi

  if [[ ! -z ${CDP_PARCEL_URLS[@]:-} ]]; then
    log_status "Downloading and distributing CDP parcels to /opt/cloudera/parcel-repo"
    download_parcels "${CDP_PARCEL_URLS[@]}"
    distribute_parcels
  fi

  # TODO: Remove patch below when/if no longer needed
  # Add additional Knox service definitions for SSB (required for CDH 7.1.7.x parcels)
  if [[ $(readlink -f /opt/cloudera/parcels/CDH | fgrep 7.1.7 | wc -l) -eq 1 ]]; then
    knox_tarball=/tmp/ssb-knox-services.tar.gz
    cat <<EOF | base64 -d > $knox_tarball
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
/wPF5pTmAKAAAA==
EOF
    target_dir=/opt/cloudera/parcels/CDH/lib/knox/data/services
    for svc in ssb-mve-api-lb  ssb-sse-api  ssb-sse-ui  ssb-sse-ui-lb  ssb-sse-ws  ssb-sse-ws-lb; do
      target_path=$target_dir/$svc
      if [[ ! -d $target_path ]]; then
        umask 022
        tar -C $target_dir -zxvf $knox_tarball $svc
        chown -R cloudera-scm:cloudera-scm $target_path
      fi
    done
    # Ensure the new services show up with a nice icon
    ssb_icon=/opt/cloudera/parcels/CDH/lib/knox/data/applications/home/app/assets/service-logos/ssb-ssc-ui.png
    if [[ -f $ssb_icon ]]; then
      target_dirs=$(find /opt/cloudera/parcels/CDH/lib/knox/data -name service-logos -type d 2>/dev/null || true)
      target_names=(ssb-sse-ui.png ssb-sse-ui-lb.png)
      for target_dir in $target_dirs; do
        for target_name in "${target_names[@]}"; do
          target_path="${target_dir}/${target_name}"
          [[ ! -f "${target_path}" ]] && cp -p "${ssb_icon}" "${target_path}"
          chmod 644 "${target_path}"
          chown cloudera-scm:cloudera-scm "${target_path}"
        done
      done
    fi
  fi

  if [[ ${CDP_CSD_URLS[@]:-} != "" ]]; then
    log_status "Installing CSDs"
    install_csds "${CDP_CSD_URLS[@]}"
  fi

  chown -R cloudera-scm:cloudera-scm /opt/cloudera

  # Change Yarn QM Config Service port to avoid conflict with NiFi - see DOCS-9707
  [[ -f /opt/cloudera/parcels/CDH/lib/queuemanager/lib/conf.yml ]] && sed -i.bak 's/8080/8079/' /opt/cloudera/parcels/CDH/lib/queuemanager/lib/conf.yml || true
  [[ -f /opt/cloudera/parcels/CDH/lib/queuemanager/lib/cpx-server.jar ]] && (
    set -e
    rm -rf /tmp/cpx
    mkdir /tmp/cpx
    cd /tmp/cpx
    jar xf /opt/cloudera/parcels/CDH/lib/queuemanager/lib/cpx-server.jar
    if [[ -f /tmp/cpx/cpx.properties ]]; then
      sed -i 's/8080/8079/' /tmp/cpx/cpx.properties
      jar cf /opt/cloudera/parcels/CDH/lib/queuemanager/lib/cpx-server.jar *
    fi
    rm -rf /tmp/cpx
  )

  # Disable EPEL repo to avoid issues during agent deployment
  sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/epel*

  log_status "Finished image preinstall"
  touch "${PREINSTALL_COMPLETED_FLAG}"
else
  log_status "Cloudera Manager repo already present, assuming this is a pre-warmed image"
  log_status "Cleaning up previous install"
  set +e
  clean_all
  set -e
fi
####### Finish packer build

log_status "Checking if executing packer build"
if [[ ! -z ${PACKER_BUILD:+x} ]]; then
  log_status "Packer build detected, exiting with success"
  sleep 2
  exit 0
else
  log_status "Packer build not detected, continuing with installation"
  sleep 2
fi

##### Start install

enable_py3
complete_host_initialization

export CDSW_DOMAIN=cdsw${PUBLIC_DNS#cdp}

log_status "Pre-warming parcels directory"
for parcel_file in $(find /opt/cloudera/parcel-repo -type f); do
  dd if="$parcel_file" of=/dev/null bs=10M &
done
# Prewarm distributed parcels
$(find /opt/cloudera/parcels -type f | xargs -n 1 -P $(nproc --all) -I{} dd if={} of=/dev/null bs=10M status=none) &

if [ "$(grep 3333 /etc/httpd/conf/httpd.conf > /dev/null && echo ok || echo no)" == "ok" ]; then
  log_status "Enabling httpd to serve local repository"
  systemctl restart httpd
fi

log_status "Update Cloudera Manager repo file with actual hostname"
sed -i "s/localhost/${CLUSTER_HOST}/" $CM_REPO_FILE

if [ "$(is_kerberos_enabled)" == "yes" ]; then
  if [[ ${KERBEROS_TYPE} == "MIT" ]]; then
    log_status "Installing Kerberos KDC"
    install_kerberos
  else
    log_status "Installing IPA client"
    install_ipa_client "$IPA_HOST"
  fi
fi

log_status "Adding users"
# After Kerberos installation so that principals are also created correctly, if needed
add_user workshop /home/workshop cdp-users
add_user admin /home/admin cdp-admins,shadow,supergroup
add_user alice /home/alice cdp-users
add_user bob /home/bob cdp-users

log_status "Creating TLS certificates"
# This is done even if ENABLE_TLS == no, since ShellInABox always needs a cert
create_certs "$IPA_HOST"

log_status "Enabling and starting ShelInABox"
systemctl enable shellinaboxd
systemctl restart shellinaboxd
# Patch ShellInABox's JS to allow for multi-line pastes
sleep 1
curl -k "https://localhost:4200/ShellInABox.js" > /var/lib/shellinabox/ShellInABox.js
cat ${BASE_DIR}/shellinabox-onpaste.js >> /var/lib/shellinabox/ShellInABox.js
# Reconfigure shellinaboxd to use the patched file
systemctl stop shellinaboxd
sed -i 's#ExecStart.*OPTS *$#& --static-file=ShellInABox.js:/var/lib/shellinabox/ShellInABox.js#' $(find /lib/systemd/system/ -name shellinaboxd.service)
# Reload and restart for changes to take effect
systemctl daemon-reload
systemctl restart shellinaboxd


if [ "${HAS_CDSW:-}" == "1" ]; then
    echo "CDSW_BUILD is set to '${CDSW_BUILD}'"
    if ! grep "CentOS Linux release 7.9" /etc/redhat-release > /dev/null 2>&1 ; then
      # CDSW requires Centos 7.5, so we trick it to believe it is...
      echo "CentOS Linux release 7.9.2009 (Core)" > /etc/redhat-release
    fi
    if [[ "${DOCKER_DEVICE}" == "" ]]; then
      echo "ERROR: Could not find any candidate devices."
      exit 1
    fi
    echo "Docker device: ${DOCKER_DEVICE}"
else
    echo "CDSW is not selected, skipping CDSW installation";
fi

log_status "Configuring PostgreSQL"
echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
/usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup initdb
sed -i 's/scram-sha-256 *$/md5/' /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf
sed -i '/host *all *all *127.0.0.1\/32 *ident/ d' /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf
cat >> /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf <<EOF
host all all 127.0.0.1/32 md5
host all all ${PRIVATE_IP}/32 md5
host all all 127.0.0.1/32 ident
host ranger rangeradmin 0.0.0.0/0 md5
EOF
if [[ ! -z ${ECS_PRIVATE_IP:-} ]]; then
  cat >> /var/lib/pgsql/${PG_VERSION}/data/pg_hba.conf <<EOF
host all all ${ECS_PRIVATE_IP}/32 md5
EOF
fi
sed -i '/^[ #]*\(password_encryption\|listen_addresses\|max_connections\|shared_buffers\|wal_buffers\|checkpoint_segments\|checkpoint_completion_target\) *=.*/ d' /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf
cat >> /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf <<EOF
password_encryption = md5
listen_addresses = '*'
max_connections = 2000
shared_buffers = 256MB
wal_buffers = 8MB
checkpoint_completion_target = 0.9
EOF

log_status "Configuring PostgreSQL for Debezium use"
sed -i '/^[ #]*\(wal_level\|max_wal_senders\|max_replication_slots\) *=.*/ d' /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf
cat >> /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf <<EOF
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
EOF

if [[ -f /opt/cloudera/security/x509/key.pem ]]; then
  log_status "Enabling TLS for PostgreSQL"
  sed -i '/^[ #]*\(ssl\|ssl_ca_file\|ssl_cert_file\|ssl_key_file\|ssl_passphrase_command\) *=.*/ d' /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf
  cat >> /var/lib/pgsql/${PG_VERSION}/data/postgresql.conf <<EOF
ssl = on
ssl_ca_file = '/opt/cloudera/security/x509/truststore.pem'
ssl_cert_file = '/opt/cloudera/security/x509/cert.pem'
ssl_key_file = '/opt/cloudera/security/x509/key.pem'
ssl_passphrase_command = 'echo ${THE_PWD}'
EOF
fi

log_status "Starting PostgreSQL"
systemctl enable postgresql-${PG_VERSION}
systemctl start postgresql-${PG_VERSION}

log_status "Creating required databases"
sudo -u postgres psql -v the_pwd="${THE_PWD}" < ${BASE_DIR}/create_db_pg.sql

log_status "Preparing Cloudera Manager database"
if [[ $CM_MAJOR_VERSION != 5 ]]; then
  SCM_PREP_DB=/opt/cloudera/cm/schema/scm_prepare_database.sh
else
  SCM_PREP_DB=/usr/share/cmf/schema/scm_prepare_database.sh
fi
$SCM_PREP_DB postgresql scm scm "${THE_PWD}"

log_status "Installing additional CSDs, if any"
for csd in $(find $BASE_DIR/csds -name "*.jar"); do
  echo "---- Copying $csd"
  cp $csd /opt/cloudera/csd/
done

log_status "Installing additional parcels, if any"
for parcel in $(find $BASE_DIR/parcels -name "*.parcel"); do
  echo "---- Copying ${parcel}"
  cp ${parcel} /opt/cloudera/parcel-repo/
  echo "---- Copying ${parcel}.sha"
  cp ${parcel}.sha /opt/cloudera/parcel-repo/
done

log_status "Setting CSDs and parcel repo permissions"
chown -R cloudera-scm:cloudera-scm /opt/cloudera/csd /opt/cloudera/parcel-repo
chmod 644 $(find /opt/cloudera/csd /opt/cloudera/parcel-repo -type f)

log_status "Starting Cloudera Manager"
systemctl enable cloudera-scm-server
systemctl enable cloudera-scm-agent
systemctl start cloudera-scm-server

log_status "Enabling password-less root login"
rm -f $KEY_FILE
ssh-keygen -f $KEY_FILE -t rsa -N ""
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat $KEY_FILE.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H $(hostname) >> ~/.ssh/known_hosts
systemctl restart sshd

log_status "Checking for additional parcels"
chmod +x ${BASE_DIR}/check-for-parcels.sh

log_status "Waiting for Cloudera Manager to be ready"
wait_for_cm

log_status "Resetting Cloudera Manager admin password"
sudo -u postgres psql -d scm -c "update users set password_hash = '${THE_PWD_HASH}', password_salt = ${THE_PWD_SALT} where user_name = 'admin'"

if [[ ${HAS_FLINK:-0} == 1 ]]; then
  # SSB 1.6.x and earlier need Python database connectors installed separately
  (
    export SSB_PYTHON=/opt/cloudera/parcels/FLINK/lib/flink/python
    export SSB_PYTHON_VENV="$SSB_PYTHON/console_venv"
    export SSB_PYTHON_BIN="$SSB_PYTHON_VENV/bin"
    if [[ -f $SSB_PYTHON_BIN/pip3 ]]; then
      log_status "Installing SSB dependencies"

      if [[ ! -e /usr/share/console_venv ]]; then
        SSB_VENV_SYMLINK_CREATED=1
        ln -s $SSB_PYTHON_VENV /usr/share/console_venv
      fi

      export PATH="$SSB_PYTHON_BIN:$PATH"
      export LD_LIBRARY_PATH="$SSB_PYTHON/console_venv/lib64"
      export PYTHONPATH="${LD_LIBRARY_PATH}"
      export PYTHONHOME="$SSB_PYTHON/console_venv/"

      mkdir -p /usr/share/python3
      pip3 install mysql-connector-python==8.0.23 psycopg2-binary==2.8.5 -t /usr/share/python3

      if [[ ${SSB_VENV_SYMLINK_CREATED:-0} -eq 1 ]]; then
        rm -f /usr/share/console_venv
      fi
    fi
  )
fi

log_status "Generating cluster template"
enable_py3
python -u $BASE_DIR/cm_template.py --cdh-major-version $CDH_MAJOR_VERSION $CM_SERVICES > $TEMPLATE_FILE

log_status "Creating cluster"
if [[ $(is_kerberos_enabled) == "yes" ]]; then
  KERBEROS_OPTION="--use-kerberos --kerberos-type $KERBEROS_TYPE"
else
  KERBEROS_OPTION=""
fi
if [[ $KERBEROS_TYPE == "IPA" ]]; then
  KERBEROS_OPTION="$KERBEROS_OPTION --ipa-host $IPA_HOST"
fi
if [ "$(is_tls_enabled)" == "yes" ]; then
  CM_TLS_OPTIONS="--use-tls"
  # In case this is a re-run and TLS was already enabled, provide the TLS truststore option
else
  CM_TLS_OPTIONS=""
fi
CM_REPO_URL=$(grep baseurl $CM_REPO_FILE | sed 's/.*=//;s/ //g')

# This is a temporary debug collection for troubleshooting some issues with QueueManager failing to start
# due to port 8081 being used.
# TODO: For debug purposes. Remove this when no longer needed
(set +e; set +x; while true; do echo "--"; date; netstat -anp | grep ":8081 .*LISTEN" > /tmp/.netstat; cat /tmp/.netstat; ps -ef | awk '$2~/('"$(grep "LISTEN " /tmp/.netstat | awk '{gsub(/\/.*/, "", $NF); print $NF}' | tr "\n" "|")"'dummy)/'; sleep .5; done) > /tmp/netstat.log &
NETSTAT_PID=$!
trap 'RET=$?; kill -9 '"$NETSTAT_PID"'; echo Setup return code: $RET' 0

log_status "Configuring Cloudera Manager"
python -u $BASE_DIR/create_cluster.py ${CLUSTER_HOST} \
  --setup-cm \
    --key-file $KEY_FILE \
    --cm-repo-url $CM_REPO_URL \
    $CM_TLS_OPTIONS \
    $KERBEROS_OPTION \
    $(get_create_cluster_tls_option)

log_status "Restarting Cloudera Manager"
systemctl restart cloudera-scm-server

log_status "Create shadow group"
chgrp shadow /etc/shadow
chmod g+r /etc/shadow

if [[ ${HAS_KNOX:-0} == 1 ]]; then
  log_status "Setting shadow permissions for Knox - needed for PAM authentication"
  id knox > /dev/null 2>&1 && usermod -G knox,hadoop,shadow knox || echo "User knox does not exist. Skipping usermod"
fi

if [[ ${HAS_ZEPPELIN:-0} == 1 ]]; then
  log_status "Ensuring Zepellin is on the shadow group for PAM auth to work (service needs restarting)"
  id zeppelin > /dev/null 2>&1 && usermod -G shadow zeppelin || echo "User zeppelin does not exist. Skipping usermod"
fi

if [[ "$(is_tls_enabled)" == "yes" ]]; then
  log_status "Tightening permissions"
  tighten_keystores_permissions
fi

log_status "Configuring Cloudera Manager agent"
if [[ ! -f /etc/cloudera-scm-agent/config.ini.original ]]; then
  cp /etc/cloudera-scm-agent/config.ini /etc/cloudera-scm-agent/config.ini.original
fi
sed -i.bak \
"s%^[# ]*server_host=.*%server_host=${CLUSTER_HOST}%"\
   /etc/cloudera-scm-agent/config.ini
if [ "$(is_tls_enabled)" == "yes" ]; then
  sed -i.bak \
's%^[# ]*use_tls=.*%use_tls=1%;'\
's%^[# ]*verify_cert_file=.*%verify_cert_file=/opt/cloudera/security/x509/truststore.pem%;'\
's%^[# ]*client_key_file=.*%client_key_file=/opt/cloudera/security/x509/key.pem%;'\
's%^[# ]*client_keypw_file=.*%client_keypw_file=/opt/cloudera/security/x509/pwfile%;'\
's%^[# ]*client_cert_file=.*%client_cert_file=/opt/cloudera/security/x509/cert.pem%'\
     /etc/cloudera-scm-agent/config.ini
fi

log_status "Restarting agent"
systemctl restart cloudera-scm-agent

log_status "Waiting for Cloudera Manager to be ready"
wait_for_cm

if [[ ${HAS_SRM:-0} == 1 ]]; then
  log_status "Creating external accounts"
  create_peer_kafka_external_account
fi

log_status "Creating cluster"
python -u $BASE_DIR/create_cluster.py ${CLUSTER_HOST} \
  --create-cluster \
    --remote-repo-usr "$(get_remote_repo_username)" \
    --remote-repo-pwd "$(get_remote_repo_password)" \
    --template $TEMPLATE_FILE \
    $(get_create_cluster_tls_option)

# TODO: remove this when no longer needed (see previous TODO)
kill -9 $NETSTAT_PID || true
trap 'echo Setup return code: $?' 0

if [[ ${HAS_RANGER:-0} == 1 && ${HAS_NIFI:-0} == 1 ]]; then
  JOB_ID=$(curl -s -k -L -X POST -u admin:"${THE_PWD}" "$(get_cm_base_url)/api/v19/clusters/OneNodeCluster/services/ranger/commands/restart" | jq '.id')
  while true; do
    [[ $(curl -s -k -L -u admin:"${THE_PWD}" "$(get_cm_base_url)/api/v19/commands/$JOB_ID" | jq -r '.active') == "false" ]] && break
    echo "Waiting for Ranger to restart"
    sleep 1
  done
  log_status "Setting Ranger policies for NiFi"
  $BASE_DIR/ranger_policies.sh "$(is_tls_enabled)"
fi

if [[ ${HAS_CEM:-} == "1" ]]; then
  log_status "Configuring and starting EFM"
  sed -i.bak \
's#^efm.server.address=.*#efm.server.address='"${CLUSTER_HOST}"'#;'\
's#^efm.server.port=.*#efm.server.port=10088#;'\
's#^efm.security.user.certificate.enabled=.*#efm.security.user.certificate.enabled=false#;'\
's#^efm.nifi.registry.enabled=.*#efm.nifi.registry.enabled=true#;'\
's#^efm.nifi.registry.url=.*#efm.nifi.registry.url=http://'"${CLUSTER_HOST}"':18080#;'\
's#^efm.nifi.registry.bucketName=.*#efm.nifi.registry.bucketName=IoT#;'\
's#^efm.heartbeat.maxAgeToKeep=.*#efm.heartbeat.maxAgeToKeep=1h#;'\
's#^efm.event.maxAgeToKeep.debug=.*#efm.event.maxAgeToKeep.debug=5m#;'\
's#^efm.db.url=.*#efm.db.url=jdbc:postgresql://'"${CLUSTER_HOST}"':5432/efm#;'\
's#^efm.db.driverClass=.*#efm.db.driverClass=org.postgresql.Driver#;'\
's#^efm.db.password=.*#efm.db.password='"${THE_PWD}"'#' /opt/cloudera/cem/efm/conf/efm.properties
  if [[ "$(is_tls_enabled)" == "yes" ]]; then
    if [[ $(compare_version "$CEM_VERSION" "1.2.2.0") != "<" ]]; then
      sed -i.bak 's#^efm.server.ssl.enabled=.*#efm.server.ssl.enabled=true#;' /opt/cloudera/cem/efm/conf/efm.properties
    fi
    sed -i.bak \
's#^efm.server.ssl.keyStore=.*#efm.server.ssl.keyStore=/opt/cloudera/security/jks/keystore.jks#;'\
's#^efm.server.ssl.keyStoreType=.*#efm.server.ssl.keyStoreType=jks#;'\
's#^efm.server.ssl.keyStorePassword=.*#efm.server.ssl.keyStorePassword='"$THE_PWD"'#;'\
's#^efm.server.ssl.keyPassword=.*#efm.server.ssl.keyPassword='"$THE_PWD"'#;'\
's#^efm.server.ssl.trustStore=.*#efm.server.ssl.trustStore=/opt/cloudera/security/jks/truststore.jks#;'\
's#^efm.server.ssl.trustStoreType=.*#efm.server.ssl.trustStoreType=jks#;'\
's#^efm.server.ssl.trustStorePassword=.*#efm.server.ssl.trustStorePassword='"$THE_PWD"'#;'\
's#^efm.security.user.certificate.enabled=.*#efm.security.user.certificate.enabled=true#;'\
's#^efm.nifi.registry.url=.*#efm.nifi.registry.url=https://'"${CLUSTER_HOST}"':18433#' /opt/cloudera/cem/efm/conf/efm.properties
  fi
  if [[ "$(is_kerberos_enabled)" == "yes" && $(compare_version "$CEM_VERSION" "1.2.2.0") != "<" ]]; then
    sed -i.bak \
's#^efm.security.user.auth.enabled=.*#efm.security.user.auth.enabled=true#;'\
's#^efm.security.user.knox.enabled=.*#efm.security.user.knox.enabled=true#;'\
's#^efm.security.user.knox.url=.*#efm.security.user.knox.url=https://'"${CLUSTER_HOST}"':9443/gateway/knoxsso/api/v1/websso#;'\
's#^efm.security.user.knox.publicKey=.*#efm.security.user.knox.publicKey=/opt/cloudera/security/x509/cert.pem#;'\
's#^efm.security.user.knox.cookieName=.*#efm.security.user.knox.cookieName=hadoop-jwt#' /opt/cloudera/cem/efm/conf/efm.properties
  fi
  echo -e "\nefm.encryption.password=${THE_PWD}${THE_PWD}" >> /opt/cloudera/cem/efm/conf/efm.properties

  retries=0
  while true; do
    sudo -u postgres psql < <( echo -e "drop database efm;\nCREATE DATABASE efm OWNER efm ENCODING 'UTF8';" )
    nohup service efm start &
    sleep 10
    set +e
    ps -ef | grep  efm.jar | grep -v grep
    cnt=$(ps -ef | grep  efm.jar | grep -v grep | wc -l)
    set -e
    if [ "$cnt" -gt 0 ]; then
      break
    fi
    if [ "$retries" == "5" ]; then
      break
    fi
    retries=$((retries + 1))
    echo "Retrying to start EFM ($retries)"
  done

  if [[ -f /opt/cloudera/cem/minifi/conf/bootstrap.conf ]]; then
    log_status "Configuring and starting MiNiFi"
    # MiNiFi Java
    sed -i.bak -E \
's%^[ #]*nifi.minifi.sensitive.props.key *=.*%nifi.minifi.sensitive.props.key=clouderaclouderacloudera%;'\
's%^[ #]*(nifi.)?c2.enable *=.*%\1c2.enable=true%;'\
's%^[ #]*(nifi.)?c2.agent.heartbeat.period *=.*%\1c2.agent.heartbeat.period=10000%;'\
's%^[ #]*(nifi.)?c2.agent.class *=.*%\1c2.agent.class=iot-1%;'\
's%^[ #]*(nifi.)?c2.agent.identifier *=.*%\1c2.agent.identifier=agent-iot-1%' /opt/cloudera/cem/minifi/conf/bootstrap.conf
    if [[ "$(is_tls_enabled)" == "yes" ]]; then
      sed -i.bak \
's%^[ #]*nifi.minifi.security.keystore *=.*%nifi.minifi.security.keystore=/opt/cloudera/security/jks/keystore.jks%;'\
's%^[ #]*nifi.minifi.security.keystoreType *=.*%nifi.minifi.security.keystoreType=JKS%;'\
's%^[ #]*nifi.minifi.security.keystorePasswd *=.*%nifi.minifi.security.keystorePasswd='"${THE_PWD}"'%;'\
's%^[ #]*nifi.minifi.security.keyPasswd *=.*%nifi.minifi.security.keyPasswd='"${THE_PWD}"'%;'\
's%^[ #]*nifi.minifi.security.truststore *=.*%nifi.minifi.security.truststore=/opt/cloudera/security/jks/truststore.jks%;'\
's%^[ #]*nifi.minifi.security.truststoreType *=.*%nifi.minifi.security.truststoreType=JKS%;'\
's%^[ #]*nifi.minifi.security.truststorePasswd *=.*%nifi.minifi.security.truststorePasswd='"${THE_PWD}"'%;'\
's%^[ #]*nifi.minifi.security.ssl.protocol *=.*%nifi.minifi.security.ssl.protocol=TLS%' /opt/cloudera/cem/minifi/conf/bootstrap.conf
    fi
    if [[ "$(is_tls_enabled)" == "yes" && $(compare_version "$CEM_VERSION" "1.2.2.0") != "<" ]]; then
      sed -i.bak -E \
's%^[ #]*nifi.c2.rest.url *=.*%nifi.c2.rest.url=https://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/heartbeat%;'\
's%^[ #]*nifi.c2.rest.url.ack *=.*%nifi.c2.rest.url.ack=https://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/acknowledge%;'\
's%^[ #]*c2.rest.path.base *=.*%c2.rest.path.base=https://'"${CLUSTER_HOST}"':10088/efm/api%;'\
's%^[ #]*(nifi.)?c2.security.truststore.location *=.*%\1c2.security.truststore.location=/opt/cloudera/security/jks/truststore.jks%;'\
's%^[ #]*(nifi.)?c2.security.truststore.password *=.*%\1c2.security.truststore.password='"${THE_PWD}"'%;'\
's%^[ #]*(nifi.)?c2.security.truststore.type *=.*%\1c2.security.truststore.type=JKS%;'\
's%^[ #]*(nifi.)?c2.security.keystore.location *=.*%\1c2.security.keystore.location=/opt/cloudera/security/jks/keystore.jks%;'\
's%^[ #]*(nifi.)?c2.security.keystore.password *=.*%\1c2.security.keystore.password='"${THE_PWD}"'%;'\
's%^[ #]*(nifi.)?c2.security.keystore.type *=.*%\1c2.security.keystore.type=JKS%;'\
's%^[ #]*(nifi.)?c2.security.need.client.auth *=.*%\1c2.security.need.client.auth=true%' /opt/cloudera/cem/minifi/conf/bootstrap.conf
    else
      sed -i.bak \
's%^[ #]*nifi.c2.rest.url *=.*%nifi.c2.rest.url=http://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/heartbeat%;'\
's%^[ #]*nifi.c2.rest.url.ack *=.*%nifi.c2.rest.url.ack=http://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/acknowledge%;'\
's%^[ #]*c2.rest.path.base *=.*%c2.rest.path.base=http://'"${CLUSTER_HOST}"':10088/efm/api%' /opt/cloudera/cem/minifi/conf/bootstrap.conf
    fi
  elif [[ -f /opt/cloudera/cem/minifi/conf/minifi.properties ]]; then
    # MiNiFi C++
    sed -i.bak -E \
's%^[ #]*(nifi.)?c2.enable *=.*%\1c2.enable=true%;'\
's%^[ #]*(nifi.)?c2.agent.protocol.class *=.*%\1c2.agent.protocol.class=RESTSender%;'\
's%^[ #]*(nifi.)?c2.agent.heartbeat.period *=.*%\1c2.agent.heartbeat.period=10000%;'\
's%^[ #]*(nifi.)?c2.agent.class *=.*%\1c2.agent.class=iot-1%;'\
's%^[ #]*(nifi.)?c2.agent.identifier *=.*%\1c2.agent.identifier=agent-iot-1%' /opt/cloudera/cem/minifi/conf/minifi.properties
    if [[ "$(is_tls_enabled)" == "yes" ]]; then
      sed -i.bak -E \
's%^[ #]*nifi.c2.rest.url *=.*%nifi.c2.rest.url=https://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/heartbeat%;'\
's%^[ #]*nifi.c2.rest.url.ack *=.*%nifi.c2.rest.url.ack=https://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/acknowledge%;'\
's%^[ #]*nifi.remote.input.secure *=.*%nifi.remote.input.secure=true%;'\
's%^[ #]*nifi.security.client.certificate *=.*%nifi.security.client.certificate=/opt/cloudera/security/x509/cert.pem%;'\
's%^[ #]*nifi.security.client.private.key *=.*%nifi.security.client.private.key=/opt/cloudera/security/x509/key.pem%;'\
's%^[ #]*nifi.security.client.pass.phrase *=.*%nifi.security.client.pass.phrase='"${THE_PWD}"'%;'\
's%^[ #]*nifi.security.client.ca.certificate *=.*%nifi.security.client.ca.certificate=/opt/cloudera/security/x509/truststore.pem%' /opt/cloudera/cem/minifi/conf/minifi.properties
    else
      sed -i.bak \
's%^[ #]*nifi.c2.rest.url *=.*%nifi.c2.rest.url=http://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/heartbeat%;'\
's%^[ #]*nifi.c2.rest.url.ack *=.*%nifi.c2.rest.url.ack=http://'"${CLUSTER_HOST}"':10088/efm/api/c2-protocol/acknowledge%' /opt/cloudera/cem/minifi/conf/minifi.properties
    fi
  fi

  if [[ -f /opt/cloudera/cem/minifi/conf/bootstrap.conf || -f /opt/cloudera/cem/minifi/conf/minifi.properties ]]; then
    systemctl enable minifi
    systemctl start minifi
  fi
fi

log_status "Enabling and starting MQTT broker"
systemctl enable mosquitto
systemctl start mosquitto

log_status "Copying demo files to a public directory"
mkdir -p /opt/demo
cp -f $BASE_DIR/simulate.py /opt/demo/
cp -f $BASE_DIR/spark.iot.py /opt/demo/
chmod -R 775 /opt/demo

# TODO: Implement Ranger DB and Setup in template
# TODO: Fix kafka topic creation once Ranger security is setup
if [[ ${HAS_KAFKA:-0} == 1 ]]; then
  log_status "Creating Kafka topics"
  auth admin
  # Avoid timeouts right after the cluster was created, which we have seen in some environments that have slow disks.
  echo "request.timeout.ms=60000" >> $KAFKA_CLIENT_PROPERTIES
  CLIENT_CONFIG_OPTION="--command-config $KAFKA_CLIENT_PROPERTIES"
  KAFKA_PORT=$(get_kafka_port)
  for topic in iot iot_enriched iot_enriched_avro; do
    kafka_cmd="kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT}"
    retry_if_needed 60 1 "$kafka_cmd --create --topic $topic --partitions 10 --replication-factor 1 || ($kafka_cmd --delete --topic $topic; exit 1)"
    kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT} --describe --topic $topic
  done
  unauth
fi

if [[ ${HAS_ATLAS:-0} == 1 ]]; then
  RETRIES=30
  ATLAS_OK=0
  if [[ "$(is_tls_enabled)" == "yes" ]]; then
    ATLAS_PROTO=https
    ATLAS_PORT=31443
  else
    ATLAS_PROTO=http
    ATLAS_PORT=31000
  fi
  while [[ $RETRIES -gt 0 ]]; do
    log_status "Wait for Atlas to be ready ($RETRIES retries left)"
    set +e
    ret_code=$(curl -w '%{http_code}' -s -o /dev/null -k --location -u admin:${THE_PWD} "${ATLAS_PROTO}://${CLUSTER_HOST}:${ATLAS_PORT}/api/atlas/v2/types/typedefs")
    set -e
    if [[ $ret_code == "200" ]]; then
      ATLAS_OK=1
      break
    fi
    RETRIES=$((RETRIES - 1))
    sleep 10
  done

  if [[ $ATLAS_OK -eq 1 ]]; then
    log_status "Loading Flink entities in Atlas"
    curl \
      -k --location \
      -u admin:${THE_PWD} \
      --request POST "${ATLAS_PROTO}://${CLUSTER_HOST}:${ATLAS_PORT}/api/atlas/v2/types/typedefs" \
      --header 'Content-Type: application/json' \
      --data '{
      "enumDefs": [],
      "structDefs": [],
      "classificationDefs": [],
      "entityDefs": [
          {
              "name": "flink_application",
              "superTypes": [
                  "Process"
              ],
              "serviceType": "flink",
              "typeVersion": "1.0",
              "attributeDefs": [
                  {
                      "name": "id",
                      "typeName": "string",
                      "cardinality": "SINGLE",
                      "isIndexable": true,
                      "isOptional": false,
                      "isUnique": true
                  },
                  {
                      "name": "startTime",
                      "typeName": "date",
                      "cardinality": "SINGLE",
                      "isIndexable": false,
                      "isOptional": true,
                      "isUnique": false
                  },
                  {
                      "name": "endTime",
                      "typeName": "date",
                      "cardinality": "SINGLE",
                      "isIndexable": false,
                      "isOptional": true,
                      "isUnique": false
                  },
                  {
                      "name": "conf",
                      "typeName": "map<string,string>",
                      "cardinality": "SINGLE",
                      "isIndexable": false,
                      "isOptional": true,
                      "isUnique": false
                  },
                  {
                      "name": "inputs",
                      "typeName": "array<string>",
                      "cardinality": "LIST",
                      "isIndexable": false,
                      "isOptional": false,
                      "isUnique": false
                  },
                  {
                      "name": "outputs",
                      "typeName": "array<string>",
                      "cardinality": "LIST",
                      "isIndexable": false,
                      "isOptional": false,
                      "isUnique": false
                  }
              ]
          }
      ],
      "relationshipDefs": []
  }'
  fi


  if [[ ${HAS_NIFI:-0} == 1 ]]; then
    log_status "Restarting NiFi Default Atlas Reporting Task"
    nifi_reporting_task_state "Default Atlas Reporting Task" "STOPPED"
    sleep 1
    nifi_reporting_task_state "Default Atlas Reporting Task" "RUNNING"
  fi
fi

if [[ ${HAS_FLINK:-0} == 1 ]]; then
  # Flink: extra workaround due to CSA-116
  log_status "Setting HDFS permissions for Flink"
  auth admin
  retry_if_needed 60 1 "hdfs dfs -chown flink:flink /user/flink"
  retry_if_needed 60 1 "hdfs dfs -mkdir /user/admin"
  retry_if_needed 60 1 "hdfs dfs -chown admin:admin /user/admin"
  unauth

  log_status "Running a quick Flink WordCount to ensure everything is ok"
  if [[ $(is_kerberos_enabled) == "yes" ]]; then
    FLINK_KRB_OPTIONS="-yD security.kerberos.login.keytab=/keytabs/admin.keytab -yD security.kerberos.login.principal=admin"
  else
    FLINK_KRB_OPTIONS=""
  fi
  nohup bash -c '
    source '$BASE_DIR'/common.sh
    echo "foo bar" > echo.txt
    auth admin
    klist
    hdfs dfs -put -f echo.txt
    hdfs dfs -rm -f -R -skipTrash hdfs:///user/admin/output
    flink run '"$FLINK_KRB_OPTIONS"' -sae -m yarn-cluster -p 2 /opt/cloudera/parcels/FLINK/lib/flink/examples/streaming/WordCount.jar --input hdfs:///user/admin/echo.txt --output hdfs:///user/admin/output
    hdfs dfs -cat hdfs:///user/admin/output/*
    unauth
    ' > $BASE_DIR/flink_test.log 2>&1 &
fi

if [ "${HAS_CDSW:-}" == "1" ]; then
  log_status "Initiating CDSW setup in the background",
  nohup python -u /tmp/resources/cdsw_setup.py $(echo "$PUBLIC_DNS" | sed -E 's/cdp.(.*).nip.io/\1/') /tmp/resources/iot_model.pkl /tmp/resources/the_pwd.txt > /tmp/resources/cdsw_setup.log 2>&1 &
fi

if [[ ! -z ${ECS_PUBLIC_DNS:-} ]]; then
  install_ecs
fi

log_status "Cleaning up"
rm -f $BASE_DIR/stack.*.sh* $BASE_DIR/stack.sh* $BASE_DIR/.license

if [[ ! -z ${CLUSTER_ID:-} ]]; then
  echo "At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"
  figlet -f small -w 300  "Cluster  ${CLUSTER_ID:-???}  deployed successfully"'!' | cowsay -n -f "$(ls -1 /usr/share/cowsay | grep "\.cow" | sed 's/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
  echo "Completed successfully: CLUSTER ${CLUSTER_ID:-???}"
  log_status "Cluster deployed successfully"
fi

