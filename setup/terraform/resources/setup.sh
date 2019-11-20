#! /bin/bash

echo "-- Commencing SingleNodeCluster Setup Script"

set -e
set -u

if [ "$USER" != "root" ]; then
  echo "ERROR: This script ($0) must be executed by root"
  exit 1
fi

CLOUD_PROVIDER=${1:-aws}
TEMPLATE=${2:-}
DOCKERDEVICE=${3:-}
NOPROMPT=${4:-}
SSH_USER=${5:-}
SSH_PWD=${6:-}

BASE_DIR=$(cd $(dirname $0); pwd -P)
KEY_FILE=${BASE_DIR}/myRSAkey

source /tmp/env.sh

# Often yum connection to Cloudera repo fails and causes the instance create to fail.
# yum timeout and retries options don't see to help in this type of failure.
# We explicitly retry a few times to make sure the build continues when these timeouts happen.
function yum_install() {
  local packages=$@
  local retries=10
  while true; do
    set +e
    yum install -d1 -y ${packages}
    RET=$?
    set -e
    if [[ ${RET} == 0 ]]; then
      break
    fi
    retries=$((retries - 1))
    if [[ ${retries} -lt 0 ]]; then
      echo 'YUM install failed!'
      break
    else
      echo 'Retrying YUM...'
    fi
  done
}

#########  Start Packer Installation

echo "-- Testing if this is a pre-packed image by looking for existing Cloudera Manager repo"
if [[ ! -f /etc/yum.repos.d/cloudera-manager.repo ]]; then
  echo "-- Cloudera Manager repo not found, assuming not prepacked"
  echo "-- Installing base dependencies"
  yum_install ${JAVA_PACKAGE_NAME} vim wget curl git bind-utils epel-release
  yum_install python-pip npm gcc-c++ make
  echo "-- Install CM and MariaDB repo"
  wget --progress=dot:giga ${CM_REPO_FILE_URL} -P /etc/yum.repos.d/
  sed -i "s#https://archive.cloudera.com/cm6#${CM_BASE_URL}#g" /etc/yum.repos.d/cloudera-manager.repo

## MariaDB 10.1
  cat - >/etc/yum.repos.d/MariaDB.repo <<EOF
  [mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

  echo "-- Running remaining binary preinstalls"
  yum clean all
  rm -rf /var/cache/yum/
  yum repolist

  yum_install cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server MariaDB-server MariaDB-client shellinabox
  npm install --quiet forever -g
  pip install --quiet --upgrade pip
  pip install --progress-bar off cm_client

  echo "-- Get and extract CEM tarball to /opt/cloudera/cem"
  mkdir -p /opt/cloudera/cem
  wget --progress=dot:giga ${CEM_URL} -P /opt/cloudera/cem
  tar -zxf /opt/cloudera/cem/CEM-${CEM_VERSION}-centos7-tars-tarball.tar.gz -C /opt/cloudera/cem
  rm -f /opt/cloudera/cem/CEM-${CEM_VERSION}-centos7-tars-tarball.tar.gz

  echo "-- Preloading large Parcels to /opt/cloudera/parcel-repo"
  mkdir -p /opt/cloudera/parcel-repo
#  wget -r -np -nd -nc --progress=dot:giga -A "parcel,sha1,sha256" ${CDH_PARCEL_REPO} -P /opt/cloudera/parcel-repo
  wget -r -np -nd -nc --progress=dot:giga -A "*el7.parcel*" "${CDH_PARCEL_REPO}" -P /opt/cloudera/parcel-repo

  echo "-- Configure and optimize the OS"
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
  echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.d/rc.local
  echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.d/rc.local
  # add tuned optimization https://www.cloudera.com/documentation/enterprise/latest/topics/cdh_admin_performance.html
  echo  "vm.swappiness = 1" >> /etc/sysctl.conf
  sysctl vm.swappiness=1
  timedatectl set-timezone UTC

  echo "-- Handle cases for cloud provider customisations"
  case "${CLOUD_PROVIDER}" in
        aws)
            echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
            systemctl restart chronyd
            ;;
        azure)
            umount /mnt/resource
            mount /dev/sdb1 /opt
            ;;
        gcp)
            ;;
        *)
            echo $"Usage: $0 {aws|azure|gcp} template-file [docker-device]"
            echo $"example: ./setup.sh azure default_template.json"
            echo $"example: ./setup.sh aws cdsw_template.json /dev/xvdb"
            exit 1
  esac

  echo "-- Configure networking"
  hostnamectl set-hostname $(hostname -f)
  if [[ -f /etc/sysconfig/network ]]; then
    sed -i "/HOSTNAME=/ d" /etc/sysconfig/network
  fi
  echo "HOSTNAME=$(hostname)" >> /etc/sysconfig/network

  iptables-save > $BASE_DIR/firewall.rules
  FWD_STATUS=$(systemctl is-active firewalld || true)
  if [[ "${FWD_STATUS}" != "unknown" ]]; then
    systemctl disable firewalld
    systemctl stop firewalld
  fi
  setenforce 0
  if [[ -f /etc/selinux/config ]]; then
    sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  fi

  echo "-- Install JDBC connector"
  wget --progress=dot:giga ${JDBC_CONNECTOR_URL} -P ${BASE_DIR}/
  TAR_FILE=$(basename ${JDBC_CONNECTOR_URL})
  BASE_NAME=${TAR_FILE%.tar.gz}
  tar zxf ${BASE_DIR}/${TAR_FILE} -C ${BASE_DIR}/
  mkdir -p /usr/share/java/
  cp ${BASE_DIR}/${BASE_NAME}/${BASE_NAME}-bin.jar /usr/share/java/mysql-connector-java.jar

  echo "-- Install CSDs"
  for url in "${CSD_URLS[@]}"; do
    echo "---- Downloading $url"
    wget --progress=dot:giga ${url} -P /opt/cloudera/csd/
  done

  echo "-- Enable password authentication"
  sed -i.bak 's/PasswordAuthentication *no/PasswordAuthentication yes/' /etc/ssh/sshd_config

  echo "-- Reset SSH user password"
  echo "$SSH_PWD" | sudo passwd --stdin "$SSH_USER"

  echo "-- Finished image preinstall"
else
  echo "-- Cloudera Manager repo already present, assuming this is a prewarmed image"
fi
####### Finish packer build

echo "-- Checking if executing packer build"
if [[ ! -z ${PACKER_BUILD+x} ]]; then
  echo "-- Packer build detected, exiting with success"
  sleep 2
  exit 0
else
  echo "-- Packer build not detected, continuing with installation"
  sleep 2
fi


##### Start install
echo "-- Set /etc/hosts"
echo "$(hostname -I) $(hostname) edge2ai-1.dim.local" >> /etc/hosts

echo "-- Generate self-signed certificate for ShellInABox with the needed SAN entries"
# Generate self-signed certificate for ShellInABox with the needed SAN entries
openssl req \
  -x509 \
  -nodes \
  -newkey 2048 \
  -keyout key.pem \
  -out cert.pem \
  -days 365 \
  -subj "/C=US/ST=California/L=San Francisco/O=Cloudera/OU=Data in Motion/CN=$(hostname -f)" \
  -extensions 'v3_user_req' \
  -config <( cat <<EOF
[ req ]
default_bits = 2048
default_md = sha256
distinguished_name = req_distinguished_name
req_extensions = v3_user_req
string_mask = utf8only

[ req_distinguished_name ]
countryName_default = XX
countryName_min = 2
countryName_max = 2
localityName_default = Default City
0.organizationName_default = Default Company Ltd
commonName_max = 64
emailAddress_max = 64

[ v3_user_req ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = DNS:$(hostname -f),IP:$(hostname -I),IP:$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
EOF
)
cat key.pem cert.pem > /var/lib/shellinabox/certificate.pem
# Enable and start ShelInABox
systemctl enable shellinaboxd
systemctl start shellinaboxd

if [[ -n "${CDSW_VERSION}" ]]; then
    echo "CDSW_VERSION is set to '${CDSW_VERSION}'"
    # CDSW requires Centos 7.5, so we trick it to believe it is...
    echo "CentOS Linux release 7.5.1810 (Core)" > /etc/redhat-release
    # If user doesn't specify a device, tries to detect a free one to use
    # Device must be unmounted and have at least 200G of space
    if [[ "${DOCKERDEVICE}" == "" ]]; then
      echo "Docker device was not specified in the command line. Will try to detect a free device to use"
      TMP_FILE=${BASE_DIR}/.device.list
      # Find devices that are not mounted and have size greater than or equal to 200G
      lsblk -o NAME,MOUNTPOINT,SIZE -s -p -n | awk '/^\// && NF == 2 && $TEMPLATE ~ /([2-9]|[0-9][0-9])[0-9][0-9]G/' > "${TMP_FILE}"
      if [[ $(cat $TMP_FILE | wc -l) == 0 ]]; then
        echo "ERROR: Could not find any candidate devices."
        exit 1
      elif [[ $(cat ${TMP_FILE} | wc -l) -gt 1 ]]; then
        echo "ERROR: Found more than 1 possible devices to use:"
        cat ${TMP_FILE}
        exit 1
      else
        DOCKERDEVICE=$(awk '{print $1}' ${TMP_FILE})
      fi
      rm -f ${TMP_FILE}
    fi
    echo "Docker device: ${DOCKERDEVICE}"
else
    echo "CDSW_VERSION is unset, skipping CDSW installation";
fi

echo "--Configure and start MariaDB"
echo "-- Configure MariaDB"
cat ${BASE_DIR}/mariadb.config > /etc/my.cnf
systemctl enable mariadb
systemctl start mariadb

echo "-- Create DBs required by CM"
mysql -u root < ${BASE_DIR}/create_db.sql

echo "-- Secure MariaDB"
mysql -u root < ${BASE_DIR}/secure_mariadb.sql

echo "-- Prepare CM database 'scm'"
/opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm cloudera

echo "-- Install additional CSDs"
for csd in $(find $BASE_DIR/csds -name "*.jar"); do
  echo "---- Copying $csd"
  cp $csd /opt/cloudera/csd/
done

echo "-- Install additional parcels"
for parcel in $(find $BASE_DIR/parcels -name "*.parcel"); do
  echo "---- Copying ${parcel}"
  cp ${parcel} /opt/cloudera/parcel-repo/
  echo "---- Copying ${parcel}.sha"
  cp ${parcel}.sha /opt/cloudera/parcel-repo/
done

echo "-- Set CSDs and parcel repo permissions"
chown -R cloudera-scm:cloudera-scm /opt/cloudera/csd /opt/cloudera/parcel-repo
chmod 644 $(find /opt/cloudera/csd /opt/cloudera/parcel-repo -type f)

echo "-- Start CM, it takes about 2 minutes to be ready"
systemctl start cloudera-scm-server

echo "-- Install and configure EFM"
EFM_TARBALL=$(find /opt/cloudera/cem/ -path "*/centos7/*" -name "efm-*-bin.tar.gz")
EFM_BASE_NAME=$(basename $EFM_TARBALL | sed 's/-bin.tar.gz//')
tar -zxf ${EFM_TARBALL} -C /opt/cloudera/cem
ln -s /opt/cloudera/cem/${EFM_BASE_NAME} /opt/cloudera/cem/efm
ln -s /opt/cloudera/cem/efm/bin/efm.sh /etc/init.d/efm
chown -R root:root /opt/cloudera/cem/${EFM_BASE_NAME}
rm -f /opt/cloudera/cem/efm/conf/efm.properties
cp $BASE_DIR/efm.properties /opt/cloudera/cem/efm/conf

echo "-- Install and configure MiNiFi"
MINIFI_TARBALL=$(find /opt/cloudera/cem/ -path "*/centos7/*" -name "minifi-[0-9]*-bin.tar.gz")
MINIFITK_TARBALL=$(find /opt/cloudera/cem/ -path "*/centos7/*" -name "minifi-toolkit-*-bin.tar.gz")
MINIFI_BASE_NAME=$(basename $MINIFI_TARBALL | sed 's/-bin.tar.gz//')
MINIFITK_BASE_NAME=$(basename $MINIFITK_TARBALL | sed 's/-bin.tar.gz//')
tar -zxf ${MINIFI_TARBALL} -C /opt/cloudera/cem
tar -zxf ${MINIFITK_TARBALL} -C /opt/cloudera/cem
ln -s /opt/cloudera/cem/${MINIFI_BASE_NAME} /opt/cloudera/cem/minifi
chown -R root:root /opt/cloudera/cem/${MINIFI_BASE_NAME}
chown -R root:root /opt/cloudera/cem/${MINIFITK_BASE_NAME}
rm -f /opt/cloudera/cem/minifi/conf/bootstrap.conf
cp $BASE_DIR/bootstrap.conf /opt/cloudera/cem/minifi/conf
/opt/cloudera/cem/minifi/bin/minifi.sh install

echo "-- Enable passwordless root login via rsa key"
ssh-keygen -f $KEY_FILE -t rsa -N ""
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat $KEY_FILE.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H $(hostname) >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

echo "-- Automate cluster creation using the CM API"
PUBLIC_IP=$(curl https://api.ipify.org/ 2>/dev/null)
PUBLIC_DNS=$(dig -x ${PUBLIC_IP} +short)

sed -i "\
s/YourHostname/$(hostname -f)/g;\
s/YourCDSWDomain/cdsw.${PUBLIC_IP}.nip.io/g;\
s/YourPrivateIP/$(hostname -I | tr -d '[:space:]')/g;\
s/YourPublicDns/$PUBLIC_DNS/g;\
s#YourDockerDevice#$DOCKERDEVICE#g;\
s#ANACONDA_PARCEL_REPO#$ANACONDA_PARCEL_REPO#g;\
s#ANACONDA_VERSION#$ANACONDA_VERSION#g;\
s#CDH_PARCEL_REPO#$CDH_PARCEL_REPO#g;\
s#CDH_PARCEL_VERSION#$CDH_PARCEL_VERSION#g;\
s#CDH_VERSION#$CDH_VERSION#g;\
s#CDSW_PARCEL_REPO#$CDSW_PARCEL_REPO#g;\
s#CDSW_VERSION#$CDSW_VERSION#g;\
s#CFM_PARCEL_REPO#$CFM_PARCEL_REPO#g;\
s#CFM_VERSION#$CFM_VERSION#g;\
s#CM_VERSION#$CM_VERSION#g;\
s#SCHEMAREGISTRY_VERSION#$SCHEMAREGISTRY_VERSION#g;\
s#STREAMS_MESSAGING_MANAGER_VERSION#$STREAMS_MESSAGING_MANAGER_VERSION#g;\
" $TEMPLATE

echo "-- Check for additional parcels"
chmod +x ${BASE_DIR}/check-for-parcels.sh
ALL_PARCELS=$(${BASE_DIR}/check-for-parcels.sh ${NOPROMPT})

if [[ "$ALL_PARCELS" == "OK" ]]; then
  sed -i "s/^CSPOPTION//" $TEMPLATE
else
  sed -i "/^CSPOPTION/ d" $TEMPLATE
fi

if [[ "$CSP_PARCEL_REPO" == "" ]]; then
  sed -i "/CSPREPO/ d" $TEMPLATE
else
  sed -i "s#CSPREPO#,"\""$CSP_PARCEL_REPO"\""#" $TEMPLATE
fi

if [[ "${CDH_VERSION:0:1}" == 7 ]]; then
  sed -i "/^CDH7OPTION/ d" $TEMPLATE
else
  sed -i "s/^CDH7OPTION//" $TEMPLATE
fi

if [[ -n "$CDSW_VERSION" ]]; then
      sed -i "s/^CDSWOPTION//" $TEMPLATE
      sed -i "s#CDSWREPO#,"\""$CDSW_PARCEL_REPO"\""#" $TEMPLATE
    else
      sed -i "/^CDSWOPTION/ d" $TEMPLATE
      sed -i "/CDSWREPO/ d" $TEMPLATE
fi

echo "-- Wait for CM to be ready before proceeding"
until $(curl --output /dev/null --silent --head --fail -u "admin:admin" http://localhost:7180/api/version); do
    echo "waiting 10s for CM to come up..";
    sleep 10;
done
echo "-- CM has finished starting"

CM_REPO_URL=$(grep baseurl /etc/yum.repos.d/cloudera-manager.repo | sed 's/.*=//;s/ //g')
python $BASE_DIR/create_cluster.py $(hostname -f) $TEMPLATE $KEY_FILE $CM_REPO_URL

echo "-- Configure and start EFM"
retries=0
while true; do
  mysql -u efm -pcloudera < <( echo -e "drop database efm;\ncreate database efm;" )
  nohup service efm start &
  sleep 10
  ps -ef | grep  efm.jar | grep -v grep
  cnt=$(ps -ef | grep  efm.jar | grep -v grep | wc -l)
  if [ "$cnt" -gt 0 ]; then
    break
  fi
  if [ "$retries" == "5" ]; then
    break
  fi
  retries=$((retries + 1))
  echo "Retrying to start EFM ($retries)"
done

echo "-- Configure and start Minifi"
yum install -y mosquitto
pip install paho-mqtt
systemctl enable mosquitto
systemctl start mosquitto

# Copy demo files to a public directory
mkdir -p /opt/demo
cp $BASE_DIR/simulate.py /opt/demo/
cp $BASE_DIR/spark.iot.py /opt/demo/
chmod -R 775 /opt/demo

# MiNiFi Install
cd ~
wget http://central.maven.org/maven2/org/apache/nifi/nifi-mqtt-nar/1.8.0/nifi-mqtt-nar-1.8.0.nar -P /opt/cloudera/cem/minifi/lib
chown root:root /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
chmod 660 /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
systemctl start minifi

# TODO: Implement Ranger DB and Setup in template
# TODO: Fix kafka topic creation once Ranger security is setup
#echo "-- Create Kafka topic (iot)"
#kafka-topics --zookeeper edge2ai-1.dim.local:2181 --create --topic iot --partitions 10 --replication-factor 1
#kafka-topics --zookeeper edge2ai-1.dim.local:2181 --describe --topic iot

echo "-- At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"

# Finish install
