#! /bin/bash

echo "-- Commencing SingleNodeCluster Setup Script"

set -e
set -u

if [ "$USER" != "root" ]; then
  echo "ERROR: This script ($0) must be executed by root"
  exit 1
fi

#########  Set variables upfront

CLOUD_PROVIDER=${1:-aws}
SSH_USER=${2:-}
SSH_PWD=${3:-}
NAMESPACE=${4:-}
DOCKER_DEVICE=${5:-}
export NAMESPACE DOCKER_DEVICE

BASE_DIR=$(cd "$(dirname $0)"; pwd -L)
# Save params
if [[ ! -f $BASE_DIR/.setup.params ]]; then
  echo "bash -x $0 '$CLOUD_PROVIDER' '$SSH_USER' '$SSH_PWD' '$NAMESPACE' '$DOCKER_DEVICE'" > $BASE_DIR/.setup.params
fi

source $BASE_DIR/common.sh
KEY_FILE=${BASE_DIR}/myRSAkey
TEMPLATE_FILE=$BASE_DIR/cluster_template.${NAMESPACE}.json

load_stack $NAMESPACE

CM_REPO_FILE=/etc/yum.repos.d/cloudera-manager.repo

export PUBLIC_IP=$(curl https://ifconfig.me 2>/dev/null || curl https://api.ipify.org/ 2> /dev/null)
if [[ ! $PUBLIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "ERROR: Could not retrieve public IP for this instance. Probably a transient error. Please try again."
  exit 1
fi

function enable_py3() {
  if [[ $(which python) != /opt/rh/rh-python36/root/usr/bin/python ]]; then
    export MANPATH=
    source /opt/rh/rh-python36/enable
  fi
}

#########  Start Packer Installation

echo "-- Ensure SElinux is disabled"
setenforce 0
if [[ -f /etc/selinux/config ]]; then
  sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi

if [ "${REMOTE_REPO_USR:-}" != "" -a "${REMOTE_REPO_PWD:-}" != "" ]; then
  wget_basic_auth="--user '$REMOTE_REPO_USR' --password '$REMOTE_REPO_PWD'"
  curl_basic_auth="-u '${REMOTE_REPO_USR}:${REMOTE_REPO_PWD}'"
else
  wget_basic_auth=""
  curl_basic_auth=""
fi

echo "-- Testing if this is a pre-packed image by looking for existing Cloudera Manager repo"
if [[ ! -f $CM_REPO_FILE ]]; then
  echo "-- Cloudera Manager repo not found, assuming not prepacked"
  echo "-- Installing EPEL repo"
  yum_install epel-release
  # The EPEL repo has intermittent refresh issues that cause errors like the one below.
  # Switch to baseurl to avoid those issues when using the metalink option.
  # Error: https://.../repomd.xml: [Errno -1] repomd.xml does not match metalink for epel
  sed -i 's/metalink=/#metalink=/;s/#*baseurl=/baseurl=/' /etc/yum.repos.d/epel*.repo
  yum clean all
  rm -rf /var/cache/yum/
  set +e
  yum repolist
  RET=$?
  set -e
  if [[ $RET != 0 ]]; then
    # baseurl failed, so we'll revert to the original metalink
    sed -i 's/#*metalink=/metalink=/;s/baseurl=/#baseurl=/' /etc/yum.repos.d/epel*.repo
    yum repolist
  fi

  echo "-- Installing base dependencies"
  yum_install ${JAVA_PACKAGE_NAME} vim wget curl git bind-utils centos-release-scl figlet cowsay
  yum_install npm gcc-c++ make shellinabox mosquitto jq transmission-cli rng-tools rh-python36 httpd

  echo "-- Installing redis (for SSB)"
  yum_install redis
  sudo systemctl start redis
  sudo systemctl enable redis

  echo "-- Install CM repo"
  if [ "${CM_REPO_AS_TARBALL_URL:-}" == "" ]; then
    retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${CM_REPO_FILE_URL}' -O '$CM_REPO_FILE'"
  else
    sed -i.bak 's/^ *Listen  *.*/Listen 3333/' /etc/httpd/conf/httpd.conf
    systemctl start httpd

    CM_REPO_AS_TARBALL_FILE=/tmp/cm-repo-as-a-tarball.tar.gz
    retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${CM_REPO_AS_TARBALL_URL}' -O '$CM_REPO_AS_TARBALL_FILE'"
    tar -C /var/www/html -xvf $CM_REPO_AS_TARBALL_FILE
    CM_REPO_ROOT_DIR=$(tar -tvf $CM_REPO_AS_TARBALL_FILE | head -1 | awk '{print $NF}')
    if [[ $CM_MAJOR_VERSION == 5 ]]; then
      CM_REPO_ROOT_DIR=${CM_REPO_ROOT_DIR}/${CM_VERSION}
    fi
    rm -f $CM_REPO_AS_TARBALL_FILE

    if [[ $CM_MAJOR_VERSION != 5 ]]; then
      # In some versions the allkeys.asc file is missing from the repo-as-tarball
      KEYS_FILE=/var/www/html/${CM_REPO_ROOT_DIR}/allkeys.asc
      if [ ! -f "$KEYS_FILE" ]; then
        KEYS_URL="$(dirname "$(dirname "$CM_REPO_AS_TARBALL_URL")")/allkeys.asc"
        retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${KEYS_URL}' -O '$KEYS_FILE'"
      fi
    fi

    cat > /etc/yum.repos.d/cloudera-manager.repo <<EOF
[cloudera-manager]
name = Cloudera Manager, Version
baseurl = http://localhost:3333/$CM_REPO_ROOT_DIR
gpgcheck = 0
EOF
  fi

  echo "-- Install Postgresql repo"
  if [[ $(rpm -qa | grep pgdg-redhat-repo- | wc -l) -eq 0 ]]; then
    yum_install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
  fi

  echo "-- Clean repos"
  yum clean all
  rm -rf /var/cache/yum/
  yum repolist

  echo "-- Install and disable Cloudera Manager"
  # NOTE: must disable PG repos for this install due to some weird dependencies on psycopg2,
  # which maps to Python 3 on the PG repo, but to Python 2 on base.
  yum_install --disablerepo="pgdg*" cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server
  systemctl disable cloudera-scm-agent
  systemctl disable cloudera-scm-server

  echo "-- Hack KNOX CSD to include [knoxsso.cookie.domain.suffix] property"
  rm -rf /tmp/knoxcsd
  for KNOX_CSD in $(ls -1 /opt/cloudera/cm/csd/KNOX*.jar 2>/dev/null || true); do
    mkdir -p /tmp/knoxcsd
    pushd /tmp/knoxcsd
    jar xvf $KNOX_CSD
    if [[ -f aux/descriptors/knoxsso.json ]]; then
      sed -i.bak 's/knoxsso.token.ttl/knoxsso.cookie.domain.suffix": "*", "knoxsso.token.ttl/' aux/descriptors/knoxsso.json
    fi
    jar cvf $KNOX_CSD *
    popd
    rm -rf /tmp/knoxcsd
  done

  echo "-- Install and disable PostgreSQL"
  yum_install postgresql10-server postgresql10 postgresql10-contrib postgresql-jdbc
  systemctl disable postgresql-10

  echo "-- Handle additional installs"
  # NPM install is flaky and fails intermittently so we will retry if needed
  retry_if_needed 5 5 "npm install --quiet forever -g"
  enable_py3
  pip install --quiet --upgrade pip
  pip install --progress-bar off cm_client paho-mqtt pytest nipyapi psycopg2-binary pyyaml jinja2 impyla
  rm -f /usr/bin/python3 /usr/bin/pip3
  ln -s /opt/rh/rh-python36/root/bin/python3 /usr/bin/python3
  ln -s /opt/rh/rh-python36/root/bin/pip3 /usr/bin/pip3

  echo "-- Install JDBC connector"
  cp /usr/share/java/postgresql-jdbc.jar /usr/share/java/postgresql-connector-java.jar
  chmod 644 /usr/share/java/postgresql-connector-java.jar

  echo "-- Install Maven"
  retry_if_needed 5 5 "curl '$MAVEN_BINARY_URL' > /tmp/apache-maven-bin.tar.gz"

  tar -C "$(get_homedir $SSH_USER)" -zxvf /tmp/apache-maven-bin.tar.gz
  rm -f /tmp/apache-maven-bin.tar.gz
  MAVEN_BIN=$(ls -d1tr "$(get_homedir $SSH_USER)"/apache-maven-*/bin | tail -1)
  echo "export PATH=\$PATH:$MAVEN_BIN" >> "$(get_homedir $SSH_USER)"/.bash_profile

  echo "-- Get and extract CEM tarball to /opt/cloudera/cem"
  mkdir -p /opt/cloudera/cem
  if [ "$CEM_URL" != "" ]; then
    CEM_TARBALL_NAME=$(basename ${CEM_URL%%\?*})
    CEM_TARBALL_PATH=/opt/cloudera/cem/${CEM_TARBALL_NAME}
    retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${CEM_URL}' -O '$CEM_TARBALL_PATH'"
    tar -zxf $CEM_TARBALL_PATH -C /opt/cloudera/cem
    rm -f $CEM_TARBALL_PATH
  else
    for url in "$EFM_TARBALL_URL" "$MINIFITK_TARBALL_URL" "$MINIFI_TARBALL_URL"; do
      TARBALL_NAME=$(basename ${url%%\?*})
      TARBALL_PATH=/opt/cloudera/cem/${TARBALL_NAME}
      retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${url}' -O '$TARBALL_PATH'"
    done
  fi

  echo "-- Install and configure EFM"
  EFM_TARBALL=$(find /opt/cloudera/cem/ -name "efm-*-bin.tar.gz")
  EFM_BASE_NAME=$(basename $EFM_TARBALL | sed 's/-bin.tar.gz//')
  tar -zxf ${EFM_TARBALL} -C /opt/cloudera/cem
  rm -f /opt/cloudera/cem/efm /etc/init.d/efm
  ln -s /opt/cloudera/cem/${EFM_BASE_NAME} /opt/cloudera/cem/efm
  ln -s /opt/cloudera/cem/efm/bin/efm.sh /etc/init.d/efm
  sed -i '1s/.*/&\n# chkconfig: 2345 20 80\n# description: EFM is a Command \& Control service for managing MiNiFi deployments/' /opt/cloudera/cem/efm/bin/efm.sh
  chkconfig --add efm
  chown -R root:root /opt/cloudera/cem/${EFM_BASE_NAME}
  sed -i.bak 's#APP_EXT_LIB_DIR=.*#APP_EXT_LIB_DIR=/usr/share/java#' /opt/cloudera/cem/efm/conf/efm.conf
  sed -i.bak \
's#^efm.server.address=.*#efm.server.address=edge2ai-1.dim.local#;'\
's#^efm.security.user.certificate.enabled=.*#efm.security.user.certificate.enabled=false#;'\
's#^efm.nifi.registry.enabled=.*#efm.nifi.registry.enabled=true#;'\
's#^efm.nifi.registry.url=.*#efm.nifi.registry.url=http://edge2ai-1.dim.local:18080#;'\
's#^efm.nifi.registry.bucketName=.*#efm.nifi.registry.bucketName=IoT#;'\
's#^efm.heartbeat.maxAgeToKeep=.*#efm.heartbeat.maxAgeToKeep=1h#;'\
's#^efm.event.maxAgeToKeep.debug=.*#efm.event.maxAgeToKeep.debug=5m#;'\
's#^efm.db.url=.*#efm.db.url=jdbc:postgresql://edge2ai-1.dim.local:5432/efm#;'\
's#^efm.db.driverClass=.*#efm.db.driverClass=org.postgresql.Driver#;'\
's#^efm.db.password=.*#efm.db.password='"${THE_PWD}"'#' /opt/cloudera/cem/efm/conf/efm.properties
  echo -e "\nefm.encryption.password=${THE_PWD}${THE_PWD}" >> /opt/cloudera/cem/efm/conf/efm.properties

  echo "-- Install and configure MiNiFi"
  MINIFI_TARBALL=$(find /opt/cloudera/cem/ -name "minifi-[0-9]*-bin.tar.gz")
  MINIFITK_TARBALL=$(find /opt/cloudera/cem/ -name "minifi-toolkit-*-bin.tar.gz")
  MINIFI_BASE_NAME=$(basename $MINIFI_TARBALL | sed 's/-bin.tar.gz//')
  MINIFITK_BASE_NAME=$(basename $MINIFITK_TARBALL | sed 's/-bin.tar.gz//')
  tar -zxf ${MINIFI_TARBALL} -C /opt/cloudera/cem
  tar -zxf ${MINIFITK_TARBALL} -C /opt/cloudera/cem
  rm -f /opt/cloudera/cem/minifi
  ln -s /opt/cloudera/cem/${MINIFI_BASE_NAME} /opt/cloudera/cem/minifi
  chown -R root:root /opt/cloudera/cem/${MINIFI_BASE_NAME}
  chown -R root:root /opt/cloudera/cem/${MINIFITK_BASE_NAME}
  rm -f /opt/cloudera/cem/minifi/conf/bootstrap.conf
  cp $BASE_DIR/bootstrap.conf /opt/cloudera/cem/minifi/conf
  /opt/cloudera/cem/minifi/bin/minifi.sh install

  echo "-- Disable services here for packer images - will reenable later"
  systemctl disable minifi

  echo "-- Download and install MQTT Processor NAR file"
  retry_if_needed 5 5 "wget --progress=dot:giga https://repo1.maven.org/maven2/org/apache/nifi/nifi-mqtt-nar/1.8.0/nifi-mqtt-nar-1.8.0.nar -P /opt/cloudera/cem/minifi/lib"
  chown root:root /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
  chmod 660 /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar

  echo "-- Preloading large Parcels to /opt/cloudera/parcel-repo"
  mkdir -p /opt/cloudera/parcel-repo
  mkdir -p /opt/cloudera/parcels
  # We want to execute ln -s within the parcels directory for preloading
  cd "/opt/cloudera/parcels"
  if [ "${#PARCEL_URLS[@]}" -gt 0 ]; then
    set -- "${PARCEL_URLS[@]}"
    while [ $# -gt 0 ]; do
      component=$1
      version=$2
      url=$3
      shift 3
      echo ">>> $component - $version - $url"
      # Download parcel manifest
      manifest_url="$(check_for_presigned_url "${url%%/}/manifest.json")"
      retry_if_needed 5 5 "curl $curl_basic_auth --silent '$manifest_url' > /tmp/manifest.json"
      # Find the parcel name for the specific component and version
      parcel_name=$(jq -r '.parcels[] | select(.parcelName | contains("'"$version"'-el7.parcel")) | select(.components[] | .name == "'"$component"'").parcelName' /tmp/manifest.json)
      # Create the hash file
      hash=$(jq -r '.parcels[] | select(.parcelName | contains("'"$version"'-el7.parcel")) | select(.components[] | .name == "'"$component"'").hash' /tmp/manifest.json)
      echo "$hash" > "/opt/cloudera/parcel-repo/${parcel_name}.sha"
      # Download the parcel file - in the background
      parcel_url="$(check_for_presigned_url "${url%%/}/${parcel_name}")"
      retry_if_needed 5 5 "wget --continue --progress=dot:giga $wget_basic_auth '${parcel_url}' -O '/opt/cloudera/parcel-repo/${parcel_name}'" &
    done
    wait
    # Create the torrent file for the parcel
    for parcel_file in /opt/cloudera/parcel-repo/*.parcel; do
      transmission-create -s 512 -o "${parcel_file}.torrent" "${parcel_file}" &
    done
    wait
    # Predistribute parcel
    for parcel_file in /opt/cloudera/parcel-repo/*.parcel; do
      tar zxf "$parcel_file" -C "/opt/cloudera/parcels" &
    done
    wait
    # Pre-activate parcels
    for parcel_file in /opt/cloudera/parcel-repo/*.parcel; do
      parcel_name="$(basename "$parcel_file")"
      product_name="${parcel_name%%-*}"
      rm -f "${product_name}"
      ln -s "${parcel_name%-*.parcel}" "${product_name}"
      touch "/opt/cloudera/parcels/${product_name}/.dont_delete"
    done
  fi
  # return to BASE_DIR for continued execution
  cd "${BASE_DIR}"

  echo "-- Install CSDs"
  for url in "${CSD_URLS[@]}"; do
    echo "---- Downloading $url"
    file_name=$(basename "${url%%\?*}")
    if [ "${REMOTE_REPO_USR:-}" != "" -a "${REMOTE_REPO_PWD:-}" != "" ]; then
      auth="--user '$REMOTE_REPO_USR' --password '$REMOTE_REPO_PWD'"
    else
      auth=""
    fi
    retry_if_needed 5 5 "wget --progress=dot:giga $wget_basic_auth '${url}' -O '/opt/cloudera/csd/${file_name}'"
    # Patch CDSW CSD so that we can use it on CDP
    if [ "${HAS_CDSW:-1}" == "1" -a "$url" == "$CDSW_CSD_URL" -a "$CM_MAJOR_VERSION" == "7" ]; then
      jar xvf /opt/cloudera/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-*.jar descriptor/service.sdl
      sed -i 's/"max" *: *"6"/"max" : "7"/g' descriptor/service.sdl
      jar uvf /opt/cloudera/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-*.jar descriptor/service.sdl
      rm -rf descriptor
    fi
  done

  chown -R cloudera-scm:cloudera-scm /opt/cloudera

  # Disable EPEL repo to avoid issues during agent deployment
  sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/epel*

  echo "-- Finished image preinstall"
else
  echo "-- Cloudera Manager repo already present, assuming this is a prewarmed image"
  set +e
  clean_all
  set -e
fi
####### Finish packer build

echo "-- Checking if executing packer build"
if [[ ! -z ${PACKER_BUILD:+x} ]]; then
  echo "-- Packer build detected, exiting with success"
  sleep 2
  exit 0
else
  echo "-- Packer build not detected, continuing with installation"
  sleep 2
fi

##### Start install

#echo "-- Prewarm parcels directory"
for parcel_file in $(find /opt/cloudera/parcel-repo -type f); do
  dd if="$parcel_file" of=/dev/null bs=10M &
done
# Prewarm distributed parcels
$(find /opt/cloudera/parcels -type f | xargs -n 1 -P $(nproc --all) -I{} dd if={} of=/dev/null bs=10M status=none) &

echo "-- Configure and optimize the OS"
echo "-- Ensure there's plenty of entropy"
systemctl enable rngd
systemctl start rngd

# Enable Python3
enable_py3

echo "-- Configure kernel parameters"
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.d/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.d/rc.local
# add tuned optimization https://www.cloudera.com/documentation/enterprise/latest/topics/cdh_admin_performance.html
echo  "vm.swappiness = 1" >> /etc/sysctl.conf
sysctl vm.swappiness=1
timedatectl set-timezone UTC

echo "-- Disable firewalls"
iptables-save > $BASE_DIR/firewall.rules
FWD_STATUS=$(systemctl is-active firewalld || true)
if [[ "${FWD_STATUS}" != "unknown" ]]; then
  systemctl disable firewalld
  systemctl stop firewalld
fi

if [ "$(grep 3333 /etc/httpd/conf/httpd.conf > /dev/null && echo ok || echo no)" == "ok" ]; then
  echo "-- Enable httpd to serve local repository"
  systemctl restart httpd
fi

echo "-- Enable password authentication"
sed -i.bak 's/PasswordAuthentication *no/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "-- Reset SSH user password"
echo "$SSH_PWD" | sudo passwd --stdin "$SSH_USER"

echo "-- Handle cases for cloud provider customisations"
case "${CLOUD_PROVIDER}" in
      aws)
          sed -i.bak '/server 169.254.169.123/ d' /etc/chrony.conf
          echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
          systemctl restart chronyd
          export PUBLIC_DNS=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
          export PRIVATE_DNS=$(curl http://169.254.169.254/latest/meta-data/local-hostname)
          export PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
          ;;
      azure)
          umount /mnt/resource
          mount /dev/sdb1 /opt
          export PUBLIC_DNS=$(TBD)
          export PRIVATE_DNS=$(TBD)
          export PRIVATE_IP=$(TBD)
          ;;
      gcp)
          export PRIVATE_DNS=$(curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/hostname)
          export PUBLIC_DNS=$PRIVATE_DNS
          export PRIVATE_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
          ;;
      *)
          export PRIVATE_DNS=$(hostname -f)
          export PUBLIC_DNS=$PRIVATE_DNS
          export PRIVATE_IP=$(hostname -I | awk '{print $1}')
esac

if [ "$PUBLIC_DNS" == "" ]; then
  echo "ERROR: Could not retrieve public DNS for this instance. Probably a transient error. Please try again."
  exit 1
fi
export CLUSTER_HOST=$PUBLIC_DNS
export CDSW_DOMAIN=cdsw.${PUBLIC_IP}.nip.io

echo "-- Set /etc/hosts - Public DNS must come first"
sed -i.bak '/edge2ai-1.dim.local/ d' /etc/hosts
echo "$PRIVATE_IP $PUBLIC_DNS $PRIVATE_DNS edge2ai-1.dim.local" >> /etc/hosts

echo "-- Configure networking"
hostnamectl set-hostname ${CLUSTER_HOST}
if [[ -f /etc/sysconfig/network ]]; then
  sed -i "/HOSTNAME=/ d" /etc/sysconfig/network
fi
echo "HOSTNAME=${CLUSTER_HOST}" >> /etc/sysconfig/network

# Create certs is TLS is enabled
if [[ $ENABLE_TLS == yes ]]; then
  create_ca
  create_certs
fi

echo "-- Generate self-signed certificate for ShellInABox with the needed SAN entries"
# Generate self-signed certificate for ShellInABox with the needed SAN entries
openssl req \
  -x509 \
  -nodes \
  -newkey 2048 \
  -keyout key.pem \
  -out cert.pem \
  -days 365 \
  -subj "/C=US/ST=California/L=San Francisco/O=Cloudera/OU=Data in Motion/CN=${CLUSTER_HOST}" \
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
subjectAltName = DNS:${CLUSTER_HOST},IP:${PRIVATE_IP},IP:${PUBLIC_IP},DNS:edge2ai-1.dim.local
EOF
)
cat key.pem cert.pem > /var/lib/shellinabox/certificate.pem
chown shellinabox:shellinabox /var/lib/shellinabox/certificate.pem
chmod 400 /var/lib/shellinabox/certificate.pem
rm -f /var/lib/shellinabox/certificate-{localhost,edge2ai-1.dim.local,${CLUSTER_HOST}}.pem
ln -s /var/lib/shellinabox/certificate.pem /var/lib/shellinabox/certificate-localhost.pem
ln -s /var/lib/shellinabox/certificate.pem /var/lib/shellinabox/certificate-edge2ai-1.dim.local.pem
ln -s /var/lib/shellinabox/certificate.pem /var/lib/shellinabox/certificate-${CLUSTER_HOST}.pem

# Enable and start ShelInABox
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
    # CDSW requires Centos 7.5, so we trick it to believe it is...
    echo "CentOS Linux release 7.5.1810 (Core)" > /etc/redhat-release
    # If user doesn't specify a device, tries to detect a free one to use
    # Device must be unmounted and have at least 200G of space
    if [[ "${DOCKER_DEVICE}" == "" ]]; then
      echo "Docker device was not specified in the command line. Will try to detect a free device to use"
      TMP_FILE=/tmp/.device.list
      # Find devices that are not mounted and have size greater than or equal to 200G
      lsblk -o NAME,MOUNTPOINT,SIZE -s -p -n | awk '/^\// && NF == 2 && $NF ~ /([2-9]|[0-9][0-9])[0-9][0-9]G/' > "${TMP_FILE}"
      if [[ $(cat $TMP_FILE | wc -l) == 0 ]]; then
        echo "ERROR: Could not find any candidate devices."
        exit 1
      elif [[ $(cat ${TMP_FILE} | wc -l) -gt 1 ]]; then
        echo "ERROR: Found more than 1 possible devices to use:"
        cat ${TMP_FILE}
        exit 1
      else
        echo "Found 1 device to use"
        cat ${TMP_FILE}
        DOCKER_DEVICE=$(awk '{print $1}' ${TMP_FILE})
      fi
      rm -f ${TMP_FILE}
    fi
    echo "Docker device: ${DOCKER_DEVICE}"
else
    echo "CDSW is not selected, skipping CDSW installation";
fi

echo "-- Configure PostgreSQL"
echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
/usr/pgsql-10/bin/postgresql-10-setup initdb
sed -i '/host *all *all *127.0.0.1\/32 *ident/ d' /var/lib/pgsql/10/data/pg_hba.conf
cat >> /var/lib/pgsql/10/data/pg_hba.conf <<EOF
host all all 127.0.0.1/32 md5
host all all ${PRIVATE_IP}/32 md5
host all all 127.0.0.1/32 ident
host ranger rangeradmin 0.0.0.0/0 md5
EOF
sed -i '/^[ #]*\(listen_addresses\|max_connections\|shared_buffers\|wal_buffers\|checkpoint_segments\|checkpoint_completion_target\) *=.*/ d' /var/lib/pgsql/10/data/postgresql.conf
cat >> /var/lib/pgsql/10/data/postgresql.conf <<EOF
listen_addresses = '*'
max_connections = 2000
shared_buffers = 256MB
wal_buffers = 8MB
checkpoint_completion_target = 0.9
EOF

echo "-- Start PostgreSQL"
systemctl enable postgresql-10
systemctl start postgresql-10

echo "-- Create DBs required by CM"
sudo -u postgres psql -v the_pwd="${THE_PWD}" < ${BASE_DIR}/create_db_pg.sql

echo "-- Prepare CM database 'scm'"
if [[ $CM_MAJOR_VERSION != 5 ]]; then
  SCM_PREP_DB=/opt/cloudera/cm/schema/scm_prepare_database.sh
else
  SCM_PREP_DB=/usr/share/cmf/schema/scm_prepare_database.sh
fi
$SCM_PREP_DB postgresql scm scm "${THE_PWD}"

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
systemctl enable cloudera-scm-server
systemctl enable cloudera-scm-agent
systemctl start cloudera-scm-server

echo "-- Enable passwordless root login via rsa key"
rm -f $KEY_FILE
ssh-keygen -f $KEY_FILE -t rsa -N ""
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat $KEY_FILE.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H $(hostname) >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

echo "-- Check for additional parcels"
chmod +x ${BASE_DIR}/check-for-parcels.sh

if [ "$(is_kerberos_enabled)" == "yes" ]; then
  echo "-- Install Kerberos KDC"
  install_kerberos
fi

# Add users - after Kerberos installation so that principals are also created correctly, if needed
add_user workshop users
add_user admin admins,shadow
add_user alice users
add_user bob users

wait_for_cm

echo "Reset CM admin password"
sudo -u postgres psql -d scm -c "update users set password_hash = '${THE_PWD_HASH}', password_salt = ${THE_PWD_SALT} where user_name = 'admin'"

enable_py3
if [[ ${HAS_FLINK:-0} == 1 ]]; then
  echo "-- Install SSB dependencies"
  mkdir -p /usr/share/python3
  pip3 install \
    mysql-connector-python==8.0.23 psycopg2-binary==2.8.5 \
    -t /usr/share/python3
fi

echo "-- Generate cluster template"
python -u $BASE_DIR/cm_template.py --cdh-major-version $CDH_MAJOR_VERSION $CM_SERVICES > $TEMPLATE_FILE

echo "-- Create cluster"
if [ "$(is_kerberos_enabled)" == "yes" ]; then
  KERBEROS_OPTION="--use-kerberos"
else
  KERBEROS_OPTION=""
fi
CM_REPO_URL=$(grep baseurl $CM_REPO_FILE | sed 's/.*=//;s/ //g')
# In case this is a re-run and TLS was already enabled, provide the TLS truststore option
TRUSTSTORE_OPTION=$([[ $(netstat -anp | grep ':7183 .*LISTEN ' | wc -l) > 0 ]] && echo "--tls-ca-cert /opt/cloudera/security/x509/truststore.pem" || echo "")
if [ "$(is_tls_enabled)" != "yes" ]; then
  python -u $BASE_DIR/create_cluster.py ${CLUSTER_HOST} \
    $TRUSTSTORE_OPTION \
    --setup-cm \
      --key-file $KEY_FILE \
      --cm-repo-url $CM_REPO_URL \
      $KERBEROS_OPTION \
    --create-cluster \
      --template $TEMPLATE_FILE
else
  python -u $BASE_DIR/create_cluster.py ${CLUSTER_HOST} \
    $TRUSTSTORE_OPTION \
    --setup-cm \
      --key-file $KEY_FILE \
      --cm-repo-url $CM_REPO_URL \
      --use-tls \
      $KERBEROS_OPTION

  # Restart CM
  systemctl restart cloudera-scm-server
  # Reconfigure agent
  if [[ ! -f /etc/cloudera-scm-agent/config.ini.original ]]; then
    cp /etc/cloudera-scm-agent/config.ini /etc/cloudera-scm-agent/config.ini.original
  fi
  sed -i.bak \
"s%^[# ]*server_host=.*%server_host=${CLUSTER_HOST}%;"\
's%^[# ]*use_tls=.*%use_tls=1%;'\
's%^[# ]*verify_cert_file=.*%verify_cert_file=/opt/cloudera/security/x509/truststore.pem%;'\
's%^[# ]*client_key_file=.*%client_key_file=/opt/cloudera/security/x509/key.pem%;'\
's%^[# ]*client_keypw_file=.*%client_keypw_file=/opt/cloudera/security/x509/pwfile%;'\
's%^[# ]*client_cert_file=.*%client_cert_file=/opt/cloudera/security/x509/cert.pem%'\
     /etc/cloudera-scm-agent/config.ini
  # Restart agent
  systemctl restart cloudera-scm-agent
  # Wait for CM to be ready
  wait_for_cm

  python -u $BASE_DIR/create_cluster.py ${CLUSTER_HOST} \
    --create-cluster \
      --template $TEMPLATE_FILE \
      --tls-ca-cert /opt/cloudera/security/x509/truststore.pem
fi

echo "Set shadow permissions - needed by Knox when using PAM authentication"
chgrp shadow /etc/shadow
chmod g+r /etc/shadow
id knox > /dev/null 2>&1 && usermod -G knox,hadoop,shadow knox || echo "User knox does not exist. Skipping usermod"
if [[ ${HAS_KNOX:-0} == 1 ]]; then
  curl -k -L -X POST -u admin:${THE_PWD} "http://${CLUSTER_HOST}:7180/api/v19/clusters/OneNodeCluster/services/knox/commands/restart"
fi

echo "-- Ensure Zepellin is on the shadow group for PAM auth to work (service needs restarting)"
id zeppelin > /dev/null 2>&1 && usermod -G shadow zeppelin || echo "User zeppelin does not exist. Skipping usermod"
if [[ ${HAS_ZEPPELIN:-0} == 1 ]]; then
  curl -k -L -X POST -u admin:${THE_PWD} "http://${CLUSTER_HOST}:7180/api/v19/clusters/OneNodeCluster/services/zeppelin/commands/restart"
fi

echo "-- Tighten permissions"
if [[ $ENABLE_TLS == yes ]]; then
  tighten_keystores_permissions
fi

echo "-- Set Ranger policies for NiFi"
if [[ ${HAS_RANGER:-0} == 1 && ${HAS_NIFI:-0} == 1 ]]; then
  $BASE_DIR/ranger_policies.sh
fi

echo "-- Configure and start EFM"
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

echo "-- Enable and start MQTT broker"
systemctl enable mosquitto
systemctl start mosquitto

echo "-- Copy demo files to a public directory"
mkdir -p /opt/demo
cp -f $BASE_DIR/simulate.py /opt/demo/
cp -f $BASE_DIR/spark.iot.py /opt/demo/
chmod -R 775 /opt/demo

echo "-- Start MiNiFi"
systemctl enable minifi
systemctl start minifi

# TODO: Implement Ranger DB and Setup in template
# TODO: Fix kafka topic creation once Ranger security is setup
if [[ ",${CM_SERVICES}," == *",KAFKA,"* ]]; then
  echo "-- Create Kafka topic (iot)"
  auth kafka
  if [[ -f $KAFKA_CLIENT_PROPERTIES ]]; then
    CLIENT_CONFIG_OPTION="--command-config $KAFKA_CLIENT_PROPERTIES"
  else
    CLIENT_CONFIG_OPTION=""
  fi
  if [ "$(is_tls_enabled)" == "yes" ]; then
    KAFKA_PORT="9093"
  else
    KAFKA_PORT="9092"
  fi
  kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT} --create --topic iot --partitions 10 --replication-factor 1
  kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT} --describe --topic iot
  kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT} --create --topic iot_enriched --partitions 10 --replication-factor 1
  kafka-topics $CLIENT_CONFIG_OPTION --bootstrap-server ${CLUSTER_HOST}:${KAFKA_PORT} --describe --topic iot_enriched
  unauth
fi

RETRIES=30
ATLAS_OK=0
while [[ $RETRIES -gt 0 ]]; do
  echo "-- Wait for Atlas to be ready ($RETRIES retries left)"
  set +e
  ret_code=$(curl -w '%{http_code}' -s -o /dev/null -k --location -u admin:${THE_PWD} "http://${CLUSTER_HOST}:31000/api/atlas/v2/types/typedefs")
  set -e
  if [[ $ret_code == "200" ]]; then
    ATLAS_OK=1
    break
  fi
  RETRIES=$((RETRIES - 1))
  sleep 10
done

if [[ $ATLAS_OK -eq 1 ]]; then
  echo "-- Load Flink entities in Atlas"
  curl \
    -k --location \
    -u admin:${THE_PWD} \
    --request POST "http://${CLUSTER_HOST}:31000/api/atlas/v2/types/typedefs" \
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

if [[ ",${CM_SERVICES}," == *",FLINK,"* ]]; then
  echo "-- Flink: extra workaround due to CSA-116"
  auth hdfs
  hdfs dfs -chown flink:flink /user/flink
  hdfs dfs -mkdir /user/${SSH_USER}
  hdfs dfs -chown ${SSH_USER}:${SSH_USER} /user/${SSH_USER}
  unauth

  echo "-- Runs a quick Flink WordCount to ensure everything is ok"
  nohup bash -c '
    source '$BASE_DIR'/common.sh
    echo "foo bar" > echo.txt
    auth flink
    klist
    hdfs dfs -put -f echo.txt
    hdfs dfs -rm -f hdfs:///user/flink/output
    flink run -sae -m yarn-cluster -p 2 /opt/cloudera/parcels/FLINK/lib/flink/examples/streaming/WordCount.jar --input hdfs:///user/flink/echo.txt --output hdfs:///user/flink/output
    hdfs dfs -cat hdfs:///user/flink/output/*
    unauth
    ' > /tmp/flink_test.log 2>&1 &
fi

echo "-- Cleaning up"
rm -f $BASE_DIR/stack.*.sh* $BASE_DIR/stack.sh*

if [[ -f /etc/workshop.conf ]]; then
  source /etc/workshop.conf
  echo "-- At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"
  figlet -f small -w 300  "Cluster  ${CLUSTER_ID:-???}  deployed successfully"'!' | cowsay -n -f "$(ls -1 /usr/share/cowsay | grep "\.cow" | sed 's/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
  echo "Completed successfully: CLUSTER ${CLUSTER_ID:-???}"
fi

