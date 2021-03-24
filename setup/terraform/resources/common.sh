#!/bin/bash

KEYTABS_DIR=/keytabs
KAFKA_CLIENT_PROPERTIES=${KEYTABS_DIR}/kafka-client.properties
KRB_REALM=WORKSHOP.COM

export THE_PWD=supersecret1
export THE_PWD_HASH=2221f4b716722c14a16f02edc6a3dbeb3a12e63affa9bde99f9ac79f2bbcb276
export THE_PWD_SALT=7690128891203708887

echo -n "$THE_PWD" > $BASE_DIR/the_pwd.txt

function is_kerberos_enabled() {
  echo $ENABLE_KERBEROS
}

function is_tls_enabled() {
  echo $ENABLE_TLS
}

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
      exit 1
    else
      echo 'Retrying YUM...'
    fi
  done
}

function get_homedir() {
  local username=$1
  getent passwd $username | cut -d: -f6
}

function get_stack_file() {
  local namespace=$1
  local base_dir=$2
  local exclude_signed=${3:-no}
  for stack in $base_dir/stack.${namespace}.sh \
               $base_dir/stack.sh; do
    if [ "${exclude_signed}" == "no" -a -e "${stack}.signed" ]; then
      stack="${stack}.signed"
      break
    elif [ -e "${stack}" ]; then
      break
    fi
  done
  echo "$stack"
}

function load_stack() {
  local namespace=$1
  local base_dir=${2:-$BASE_DIR}
  local validate_only=${3:-no}
  local exclude_signed=${4:-}
  local stack_file=$(get_stack_file $namespace $base_dir $exclude_signed)
  source $stack_file
  # export all stack vars
  for var_name in $(grep -h "^[A-Z0-9_]*=" $stack_file | sed 's/=.*//' | sort -u); do
    eval "export $var_name"
  done
  CM_SERVICES=$(echo "$CM_SERVICES" | tr "[a-z]" "[A-Z]")
  # set service selection flags
  for svc_name in $(echo "$CM_SERVICES" | tr "," " "); do
    eval "export HAS_${svc_name}=1"
  done
  # check for Kerberos
  ENABLE_KERBEROS=$(echo "${ENABLE_KERBEROS:-NO}" | tr a-z A-Z)
  if [ "$ENABLE_KERBEROS" == "YES" -o "$ENABLE_KERBEROS" == "TRUE" -o "$ENABLE_KERBEROS" == "1" ]; then
    ENABLE_KERBEROS=yes
  else
    ENABLE_KERBEROS=no
  fi
  ENABLE_TLS=$(echo "${ENABLE_TLS:-NO}" | tr a-z A-Z)
  if [ "$ENABLE_TLS" == "YES" -o "$ENABLE_TLS" == "TRUE" -o "$ENABLE_TLS" == "1" ]; then
    ENABLE_TLS=yes
  else
    ENABLE_TLS=no
  fi
  export ENABLE_KERBEROS ENABLE_TLS
  prepare_keytabs_dir
}

function prepare_keytabs_dir() {
  if [ "$validate_only" == "no" ]; then
    mkdir -p $KEYTABS_DIR

    # Create a client properties file for Kafka clients
    if [[ $(is_kerberos_enabled) == yes && $(is_tls_enabled) == yes ]]; then
      cat > ${KAFKA_CLIENT_PROPERTIES} <<EOF
security.protocol=SASL_SSL
sasl.mechanism=GSSAPI
sasl.kerberos.service.name=kafka
ssl.truststore.location=/opt/cloudera/security/jks/truststore.jks
EOF
    elif [[ $(is_kerberos_enabled) == yes ]]; then
      cat > ${KAFKA_CLIENT_PROPERTIES} <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=GSSAPI
sasl.kerberos.service.name=kafka
EOF
    elif [[ $(is_tls_enabled) == yes ]]; then
      cat > ${KAFKA_CLIENT_PROPERTIES} <<EOF
security.protocol=SSL
ssl.truststore.location=/opt/cloudera/security/jks/truststore.jks
EOF
    fi

    # Create a jaas.conf file
    if [[ $(is_kerberos_enabled) == yes ]]; then
      cat > ${KEYTABS_DIR}/jaas.conf <<EOF
KafkaClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useTicketCache=true;
};
EOF
    fi

  fi
}

function check_vars() {
  local stack_file=$1; shift
  local errors=0
  while [ $# -gt 0 ]; do
    local var_name=$1; shift
    if [ "$(eval "echo \${${var_name}:-}")" == "" ]; then
      echo "ERROR: The required property ${var_name} is not set" > /dev/stderr
      errors=1
    fi
  done
  echo $errors
}

function validate_stack() {
  local namespace=$1
  local base_dir=${2:-$BASE_DIR}
  local stack_file=$(get_stack_file $namespace $base_dir exclude-signed)
  load_stack "$namespace" "$base_dir" validate_only exclude-signed
  errors=0

  # validate required variables
  if [ "$(check_vars "$stack_file" \
            CDH_MAJOR_VERSION CM_MAJOR_VERSION CM_SERVICES \
            ENABLE_KERBEROS JAVA_PACKAGE_NAME MAVEN_BINARY_URL)" != "0" ]; then
    errors=1
  fi

  if [ "${HAS_CDSW:-}" == "1" ]; then
    if [ "$(check_vars "$stack_file" \
              CDSW_BUILD CDSW_CSD_URL)" != "0" ]; then
      errors=1
    fi
  fi

  if [[ "${CDH_VERSION}" == *"6."* || "${CDH_VERSION}" == *"7.0."* || "${CDH_VERSION}" == *"7.1.0"* ]]; then
    if [ "${HAS_SCHEMAREGISTRY:-}" == "1" -o "${HAS_SMM:-}" == "1" -o "${HAS_SRM:-}" == "1" ]; then
      if [ "$(check_vars "$stack_file" \
                CSP_PARCEL_REPO SCHEMAREGISTRY_CSD_URL \
                STREAMS_MESSAGING_MANAGER_CSD_URL \
                STREAMS_REPLICATION_MANAGER_CSD_URL)" != "0" ]; then
        errors=1
      fi
    fi
  fi

  if [ "${HAS_NIFI:-}" == "1" ]; then
    if [ "$(check_vars "$stack_file" \
              CFM_NIFIREG_CSD_URL CFM_NIFI_CSD_URL)" != "0" ]; then
      errors=1
    fi
  fi

  if [ "${HAS_FLINK:-}" == "1" ]; then
    if [ "$(check_vars "$stack_file" FLINK_CSD_URL)" != "0" ]; then
      errors=1
    fi
  fi

  if [ ! \( "${CEM_URL:-}" != "" -a "${EFM_TARBALL_URL:-}${MINIFITK_TARBALL_URL:-}${MINIFI_TARBALL_URL:-}" == "" \) -a \
       ! \( "${CEM_URL:-}" == "" -a "${EFM_TARBALL_URL:-}" != "" -a "${MINIFITK_TARBALL_URL:-}" != "" -a "${MINIFI_TARBALL_URL:-}" != "" \) ]; then
    echo "ERROR: The following parameter combinations are mutually exclusive:" > /dev/stderr
    echo "         - CEM_URL must be specified" > /dev/stderr
    echo "           OR" > /dev/stderr
    echo "         - EFM_TARBALL_URL and MINIFITK_TARBALL_URL and MINIFI_TARBALL_URL must be specified" > /dev/stderr
    errors=1
  fi

  if [ ! \( "${CM_BASE_URL:-}" != "" -a "${CM_REPO_FILE_URL:-}" != "" -a "${CM_REPO_AS_TARBALL_URL:-}" == "" \) -a \
       ! \( "${CM_BASE_URL:-}${CM_REPO_FILE_URL:-}" == "" -a "${CM_REPO_AS_TARBALL_URL:-}" != "" \) ]; then
    echo "ERROR: The following parameter combinations are mutually exclusive:" > /dev/stderr
    echo "         - CM_BASE_URL and CM_REPO_FILE_URL must be specified" > /dev/stderr
    echo "           OR" > /dev/stderr
    echo "         - CM_REPO_AS_TARBALL_URL must be specified" > /dev/stderr
    errors=1
  fi

  set -- "${PARCEL_URLS[@]:-}" "${CSD_URLS[@]:-}"
  local has_paywall_url=0
  while [ $# -gt 0 ]; do
    local url=$1; shift
    if [[ "$url" == *"/p/"* ]]; then
      has_paywall_url=1
      break
    fi
  done
  if [ "$has_paywall_url" == "1" ]; then
    if [ "${REMOTE_REPO_PWD:-}" == "" -o "${REMOTE_REPO_USR:-}" == "" ]; then
      echo "ERROR: REMOTE_REPO_USR and REMOTE_REPO_PWD must be specified when using paywall URLs" > /dev/stderr
      errors=1
    fi
  fi

  if [ "$errors" != "0" ]; then
    echo "ERROR: Please fix the errors above in the configuration file $stack_file and try again." > /dev/stderr
    exit 1
  fi
}

function check_for_presigned_url() {
  local url="$1"
  url_file=$(get_stack_file $NAMESPACE $BASE_DIR exclude-signed).urls
  signed_url=""
  if [ -s "$url_file" ]; then
    signed_url="$(fgrep "${url}-->" "$url_file" | sed 's/.*-->//')"
  fi
  if [ "$signed_url" != "" ]; then
    echo "$signed_url"
  else
    echo "$url"
  fi
}

function auth() {
  local princ=$1
  local username=${princ%%/*}
  username=${username%%@*}
  local keytab_file=${KEYTABS_DIR}/${username}.keytab
  if [ -f $keytab_file ]; then
    kinit -kt $keytab_file $princ
    export KAFKA_OPTS="-Djava.security.auth.login.config=${KEYTABS_DIR}/jaas.conf"
  else
    export HADOOP_USER_NAME=$username
  fi
}

function unauth() {
  if [[ $(is_kerberos_enabled) == yes ]]; then
    kdestroy || true
    unset KAFKA_OPTS
  else
    unset HADOOP_USER_NAME
  fi
}

function add_user() {
  local princ=$1
  local groups=${2:-}

  # Ensure OS user exists
  local username=${princ%%/*}
  username=${username%%@*}
  if [ "$(getent passwd $username > /dev/null && echo exists || echo does_not_exist)" == "does_not_exist" ]; then
    useradd -U $username
    echo -e "${THE_PWD}\n${THE_PWD}" | passwd $username
  fi

  # Add user to groups
  if [[ $groups != "" ]]; then
    # Ensure groups exist
    for group in $(echo "$groups" | sed 's/,/ /g'); do
      groupadd -f $group
    done
    usermod -G $groups $username
  fi

  if [ "$(is_kerberos_enabled)" == "yes" ]; then
    # Create Kerberos principal
    (sleep 1 && echo -e "${THE_PWD}\n${THE_PWD}") | /usr/sbin/kadmin.local -q "addprinc $princ"
    mkdir -p ${KEYTABS_DIR}

    # Create keytab
    echo -e "addent -password -p $princ -k 0 -e aes256-cts\n${THE_PWD}\nwrite_kt ${KEYTABS_DIR}/$username.keytab" | ktutil
    chmod 444 ${KEYTABS_DIR}/$username.keytab

    # Create a jaas.conf file
    cat > ${KEYTABS_DIR}/jaas-${username}.conf <<EOF
KafkaClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab="${KEYTABS_DIR}/${username}.keytab"
  principal="${princ}@${KRB_REALM}";
};
EOF
  fi
}

function install_kerberos() {
  krb_server=$(hostname -f)
  krb_realm_lc=$( echo $KRB_REALM | tr A-Z a-z )

  # Install Kerberos packages
  yum_install krb5-libs krb5-server krb5-workstation

  # Ensure entropy
  yum_install rng-tools
  systemctl start rngd
  cat /proc/sys/kernel/random/entropy_avail

  # Update krb5.conf
  cat > /etc/krb5.conf <<EOF
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_realm = $KRB_REALM

[realms]
 $KRB_REALM = {
  kdc = $krb_server
  admin_server = $krb_server
 }

[domain_realm]
 .$krb_realm_lc = $KRB_REALM
 $krb_realm_lc = $KRB_REALM
EOF

  # Update kdc.conf
  cat > /var/kerberos/krb5kdc/kdc.conf <<EOF
[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 $KRB_REALM = {
  max_renewable_life = 7d 0h 0m 0s
  #master_key_type = aes256-cts
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal camellia256-cts:normal camellia128-cts:normal des-hmac-sha1:normal des-cbc-md5:normal des-cbc-crc:normal
 }
EOF

  # Create database
  /usr/sbin/kdb5_util create -s -P ${THE_PWD}

  # Update kadm5.acl
  cat > /var/kerberos/krb5kdc/kadm5.acl <<EOF
*/admin@$KRB_REALM    *
EOF

  # Create CM principal
  add_user scm/admin

  # Set maxrenewlife for krbtgt
  # IMPORTANT: You must explicitly set this, even if the default is already set correctly.
  #            Failing to do so will cause some services to fail.

  kadmin.local -q "modprinc -maxrenewlife 7day krbtgt/$KRB_REALM@$KRB_REALM"

  # Start Kerberos
  systemctl enable krb5kdc
  systemctl enable kadmin
  systemctl start krb5kdc
  systemctl start kadmin

  # Add service principals
  add_user hdfs
  add_user yarn
  add_user kafka
  add_user flink
}

function create_ca() {
  export CA_DIR=/opt/cloudera/security/ca
  export CA_KEY=$CA_DIR/ca-key.pem
  export CA_KEY_PWD=${THE_PWD}
  export ROOT_PEM=$CA_DIR/ca-cert.pem
  export CA_CONF=$CA_DIR/openssl.cnf
  export CA_EMAIL=admin@cloudera.com

  mkdir -p $CA_DIR/newcerts
  touch $CA_DIR/index.txt
  echo "unique_subject = no" > $CA_DIR/index.txt.attr
  hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/random > $CA_DIR/serial

  # Generate CA key
  openssl genrsa \
    -out ${CA_KEY} \
    -aes256 \
    -passout pass:${CA_KEY_PWD} \
    2048
  chmod 400 ${CA_KEY}

  # Create the CA configuration
  cat > $CA_CONF <<EOF
HOME = ${CA_DIR}
RANDFILE = ${CA_DIR}/.rnd

[ ca ]
default_ca = CertToolkit # The default ca section

[ CertToolkit ]
dir = $HOME
database = $CA_DIR/index.txt # database index file.
serial = $CA_DIR/serial # The current serial number
new_certs_dir = $CA_DIR/newcerts # default place for new certs.
certificate = $ROOT_PEM # The CA certificate
private_key = $CA_KEY # The private key
default_md = sha256 # use public key default MD
unique_subject = no # Set to 'no' to allow creation of
# several ctificates with same subject.
policy = policy_any
preserve = no # keep passed DN ordering
default_days = 4000

name_opt = ca_default # Subject Name options
cert_opt = ca_default # Certificate field options

copy_extensions = copy

[ req ]
default_bits = 2048
default_md = sha256
distinguished_name = req_distinguished_name
string_mask = utf8only

[ req_distinguished_name ]
countryName_default = XX
countryName_min = 2
countryName_max = 2
localityName_default = Default City
0.organizationName_default = Default Company Ltd
commonName_max = 64
emailAddress_max = 64

[ policy_any ]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[ v3_common_extensions ]

[ v3_user_extensions ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer

[ v3_ca_extensions ]
basicConstraints = CA:TRUE
subjectAltName=email:${CA_EMAIL}
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
EOF

  # Generate CA certificate
  openssl req -x509 -new -nodes \
    -sha256 \
    -key ${CA_KEY} \
    -days 4000 \
    -out ${ROOT_PEM} \
    -passin pass:${CA_KEY_PWD} \
    -passout pass:${CA_KEY_PWD} \
    -extensions v3_ca_extensions \
    -config ${CA_CONF} \
    -subj '/C=US/ST=California/L=San Francisco/O=Cloudera/OU=PS/CN=CertToolkitRootCA'
}

function create_certs() {
  export KEY_PEM=/opt/cloudera/security/x509/key.pem
  export CSR_PEM=/opt/cloudera/security/x509/host.csr
  export HOST_PEM=/opt/cloudera/security/x509/host.pem
  export KEY_PWD=${THE_PWD}

  # Generated files
  export CERT_PEM=/opt/cloudera/security/x509/cert.pem
  export TRUSTSTORE_PEM=/opt/cloudera/security/x509/truststore.pem
  export KEYSTORE_JKS=/opt/cloudera/security/jks/keystore.jks
  export TRUSTSTORE_JKS=/opt/cloudera/security/jks/truststore.jks
  export KEYSTORE_PWD=$KEY_PWD
  export TRUSTSTORE_PWD=${THE_PWD}

  mkdir -p $(dirname $KEY_PEM) $(dirname $CSR_PEM) $(dirname $HOST_PEM) /opt/cloudera/security/jks

  # Create private key
  openssl genrsa -des3 -out ${KEY_PEM} -passout pass:${KEY_PWD} 2048

  # Create CSR
  local public_ip=$(curl https://ifconfig.me 2>/dev/null || curl https://api.ipify.org/ 2> /dev/null)
  export ALT_NAMES=DNS:edge2ai-1.dim.local,DNS:$(hostname -f),IP:$(hostname -I),IP:${public_ip}
  openssl req\
    -new\
    -key ${KEY_PEM} \
    -subj "/C=US/ST=California/L=San Francisco/O=Cloudera/OU=PS/CN=$(hostname -f)" \
    -out ${CSR_PEM} \
    -passin pass:${KEY_PWD} \
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
subjectAltName = $ALT_NAMES
EOF
  )

  # Sign cert
  openssl ca \
    -config ${CA_CONF} \
    -in ${CSR_PEM} \
    -key ${CA_KEY_PWD} \
    -batch \
    -extensions v3_user_extensions | \
  openssl x509 > $HOST_PEM

  # Create PEM truststore
  rm -f $TRUSTSTORE_PEM
  cp $ROOT_PEM $TRUSTSTORE_PEM

  # Create PEM combined certificate
  cat > $CERT_PEM <<EOF
$(cat $HOST_PEM)
EOF

  # Generate JKS keystore
  rm -f temp.p12

  openssl pkcs12 -export \
   -in $CERT_PEM \
   -inkey <(openssl rsa -in $KEY_PEM -passin pass:$KEY_PWD) \
   -out temp.p12 \
   -passout pass:temptemptemp \
   -name $(hostname -f)

  rm -f $KEYSTORE_JKS
  keytool \
   -importkeystore \
   -alias $(hostname -f) \
   -srcstoretype PKCS12 \
   -srckeystore temp.p12 \
   -destkeystore $KEYSTORE_JKS \
   -srcstorepass temptemptemp \
   -deststorepass $KEYSTORE_PWD \
   -destkeypass $KEYSTORE_PWD

  rm -f temp.p12

  # Generate JKS truststore
  rm -f $TRUSTSTORE_JKS
  keytool \
    -importcert \
    -keystore $TRUSTSTORE_JKS \
    -storepass $TRUSTSTORE_PWD \
    -file $TRUSTSTORE_PEM \
    -alias rootca \
    -trustcacerts \
    -no-prompt

  # Create agent password file
  echo $KEY_PWD > /opt/cloudera/security/x509/pwfile
  chown cloudera-scm:cloudera-scm /opt/cloudera/security/x509/pwfile
  chmod 400 /opt/cloudera/security/x509/pwfile

  # Create HUE LB password file
  mkdir -p /opt/cloudera/security/hue
  echo $KEY_PWD > /opt/cloudera/security/hue/loadbalancer.pw
  chmod 755 /opt/cloudera/security/hue
  chmod 444 /opt/cloudera/security/hue/loadbalancer.pw

  # Set permissions
  chown cloudera-scm:cloudera-scm $KEY_PEM $KEYSTORE_JKS $CERT_PEM $TRUSTSTORE_PEM $TRUSTSTORE_JKS
  chmod 444 $KEY_PEM $KEYSTORE_JKS
  chmod 444 $CERT_PEM $TRUSTSTORE_PEM $TRUSTSTORE_JKS

}

function tighten_keystores_permissions() {
  # Set permissions for HUE LB password file
  chown -R hue:hue /opt/cloudera/security/hue
  chmod 500 /opt/cloudera/security/hue
  chmod 400 /opt/cloudera/security/hue/loadbalancer.pw

  # Set permissions and ACLs
  chmod 440 $KEY_PEM $KEYSTORE_JKS

  set +e # Just in case some of the users do not exist
  sudo setfacl -m user:atlas:r--,group:atlas:r-- $KEYSTORE_JKS
  sudo setfacl -m user:cruisecontrol:r--,group:cruisecontrol:r-- $KEYSTORE_JKS
  sudo setfacl -m user:flink:r--,group:flink:r-- $KEYSTORE_JKS
  sudo setfacl -m user:hbase:r--,group:hbase:r-- $KEYSTORE_JKS
  sudo setfacl -m user:hdfs:r--,group:hdfs:r-- $KEYSTORE_JKS
  sudo setfacl -m user:hive:r--,group:hive:r-- $KEYSTORE_JKS
  sudo setfacl -m user:httpfs:r--,group:httpfs:r-- $KEYSTORE_JKS
  sudo setfacl -m user:impala:r--,group:impala:r-- $KEYSTORE_JKS
  sudo setfacl -m user:kafka:r--,group:kafka:r-- $KEYSTORE_JKS
  sudo setfacl -m user:knox:r--,group:knox:r-- $KEYSTORE_JKS
  sudo setfacl -m user:livy:r--,group:livy:r-- $KEYSTORE_JKS
  sudo setfacl -m user:nifi:r--,group:nifi:r-- $KEYSTORE_JKS
  sudo setfacl -m user:nifiregistry:r--,group:nifiregistry:r-- $KEYSTORE_JKS
  sudo setfacl -m user:oozie:r--,group:oozie:r-- $KEYSTORE_JKS
  sudo setfacl -m user:ranger:r--,group:ranger:r-- $KEYSTORE_JKS
  sudo setfacl -m user:schemaregistry:r--,group:schemaregistry:r-- $KEYSTORE_JKS
  sudo setfacl -m user:solr:r--,group:solr:r-- $KEYSTORE_JKS
  sudo setfacl -m user:spark:r--,group:spark:r-- $KEYSTORE_JKS
  sudo setfacl -m user:streamsmsgmgr:r--,group:streamsmsgmgr:r-- $KEYSTORE_JKS
  sudo setfacl -m user:streamsrepmgr:r--,group:streamsrepmgr:r-- $KEYSTORE_JKS
  sudo setfacl -m user:yarn:r--,group:hadoop:r-- $KEYSTORE_JKS
  sudo setfacl -m user:zeppelin:r--,group:zeppelin:r-- $KEYSTORE_JKS
  sudo setfacl -m user:zookeeper:r--,group:zookeeper:r-- $KEYSTORE_JKS

  sudo setfacl -m user:hue:r--,group:hue:r-- $KEY_PEM
  sudo setfacl -m user:impala:r--,group:impala:r-- $KEY_PEM
  sudo setfacl -m user:kudu:r--,group:kudu:r-- $KEY_PEM
  sudo setfacl -m user:streamsmsgmgr:r--,group:streamsmsgmgr:r-- $KEY_PEM
  set -e
}

function wait_for_cm() {
  echo "-- Wait for CM to be ready before proceeding"
  while true; do
    for pwd in admin ${THE_PWD}; do
      local result=$(
        curl \
          --fail \
          --head \
          --insecure \
          --location \
          --output /dev/null \
          --silent \
          --user "admin:${pwd}" \
          --write-out "%{http_code}" \
          http://localhost:7180/api/version
      )
      if [[ $result == "200" ]]; then
        break 2
      fi
    done
    echo "waiting 10s for CM to come up.."
    sleep 10
  done
  echo "-- CM has finished starting"
}

function retry_if_needed() {
  local retries=$1
  local wait_secs=$2
  local cmd=$3
  local ret=0
  while [[ $retries -ge 0 ]]; do
    set +e
    eval "$cmd"
    ret=$?
    set -e
    if [[ $ret -eq 0 ]]; then
      return 0
    else
      retries=$((retries-1))
      if [[ $retries -lt 0 ]]; then
        return $ret
      fi
    fi
    sleep $wait_secs
    echo "Retrying command [$cmd]"
  done
}

#
# Template parsing functions
#

function service_port() {
  local template_file=$1
  local service_type=$2
  local role_type=$3
  local non_tls_config=$4
  local tls_config=${5:-}

  if [[ $tls_config == "" || $ENABLE_TLS != "yes" ]]; then
    local config=$non_tls_config
  else
    local config=$tls_config
  fi
  if [[ $role_type != "" ]]; then
    jq -r '.services[] | select(.serviceType == "'"$service_type"'").roleConfigGroups[] | select(.roleType == "'"$role_type"'").configs[] | select(.name == "'"$config"'").value' $template_file
  else
    jq -r '.services[] | select(.serviceType == "'"$service_type"'").serviceConfigs[] | select(.name == "'"$config"'").value' $template_file
  fi
}

function get_service_urls() {
  local tmp_template_file=/tmp/template.$$
  load_stack $NAMESPACE $BASE_DIR/resources validate_only exclude_signed
  CLUSTER_HOST=dummy PRIVATE_IP=dummy PUBLIC_DNS=dummy DOCKER_DEVICE=dummy CDSW_DOMAIN=dummy \
  python $BASE_DIR/resources/cm_template.py --cdh-major-version $CDH_MAJOR_VERSION $CM_SERVICES > $tmp_template_file

  local cm_port=$([[ $ENABLE_TLS == "yes" ]] && echo 7183 || echo 7180)
  local protocol=$([[ $ENABLE_TLS == "yes" ]] && echo https || echo http)
  (
    echo "Cloudera Manager=${protocol}://{host}:${cm_port}/"
    (
      echo "Edge Flow Manager=http://{host}:10080/efm/ui/"
      if [[ ${HAS_FLINK:-0} == 1 ]]; then
        local flink_port=$(service_port $tmp_template_file FLINK FLINK_HISTORY_SERVER historyserver_web_port)
        echo "Flink Dashboard=${protocol}://{host}:${flink_port}/"
        local ssb_port=$(service_port $tmp_template_file SQL_STREAM_BUILDER STREAMING_SQL_CONSOLE console.port console.secure.port)
        echo "SQL Stream Builder=${protocol}://{host}:${ssb_port}/"
      fi
      if [[ ${HAS_NIFI:-0} == 1 ]]; then
        local nifi_port=$(service_port $tmp_template_file NIFI NIFI_NODE nifi.web.http.port nifi.web.https.port)
        local nifireg_port=$(service_port $tmp_template_file NIFIREGISTRY NIFI_REGISTRY_SERVER nifi.registry.web.http.port nifi.registry.web.https.port)
        echo "NiFi=${protocol}://{host}:${nifi_port}/nifi/"
        echo "NiFi Registry=${protocol}://{host}:${nifireg_port}/nifi-registry/"
      fi
      if [[ ${HAS_SCHEMAREGISTRY:-0} == 1 ]]; then
        local schemareg_port=$(service_port $tmp_template_file SCHEMAREGISTRY SCHEMA_REGISTRY_SERVER schema.registry.port schema.registry.ssl.port)
        echo "Schema Registry=${protocol}://{host}:${schemareg_port}/"
      fi
      if [[ ${HAS_SMM:-0} == 1 ]]; then
        local smm_port=$(service_port $tmp_template_file STREAMS_MESSAGING_MANAGER STREAMS_MESSAGING_MANAGER_UI streams.messaging.manager.ui.port)
        echo "SMM=${protocol}://{host}:${smm_port}/"
      fi
      if [[ ${HAS_HUE:-0} == 1 ]]; then
        local hue_port=$(service_port $tmp_template_file HUE HUE_LOAD_BALANCER listen)
        echo "Hue=${protocol}://{host}:${hue_port}/"
      fi
      if [[ ${HAS_ATLAS:-0} == 1 ]]; then
        local atlas_port=$(service_port $tmp_template_file ATLAS ATLAS_SERVER atlas_server_http_port atlas_server_https_port)
        echo "Atlas=${protocol}://{host}:${atlas_port}/"
      fi
      if [[ ${HAS_RANGER:-0} == 1 ]]; then
        local ranger_port=$(service_port $tmp_template_file RANGER "" ranger_service_http_port ranger_service_https_port)
        echo "Ranger=${protocol}://{host}:${ranger_port}/"
      fi
      if [[ ${HAS_KNOX:-0} == 1 ]]; then
        local knox_port=$(service_port $tmp_template_file KNOX KNOX_GATEWAY gateway_port)
        echo "Knox=${protocol}://{host}:${knox_port}/gateway/homepage/home/"
      fi
      if [[ ${HAS_CDSW:-0} == 1 ]]; then
        echo "CDSW=${protocol}://cdsw.{ip_address}.nip.io/"
      fi
    ) | sort
  ) | tr "\n" "," | sed 's/,$//'
  rm -f $tmp_template_file
}

function clean_all() {
  systemctl stop cloudera-scm-server cloudera-scm-agent cloudera-scm-supervisord kadmin krb5kdc chronyd mosquitto postgresql-10 httpd shellinaboxd
  service minifi stop
  service efm stop
  pids=$(ps -ef | grep cloudera | grep -v grep | awk '{print $2}')
  if [[ $pids != "" ]]; then
    kill -9 $pids
  fi

  if [[ -d /opt/cloudera/parcels/CDSW/scripts ]]; then
    while true; do /opt/cloudera/parcels/CDSW/scripts/stop-cdsw-app-standalone.sh && break; done
    while true; do /opt/cloudera/parcels/CDSW/scripts/stop-kubelet-standalone.sh && break; done
    while true; do /opt/cloudera/parcels/CDSW/scripts/stop-dockerd-standalone.sh && break; done
  fi

  mounts=$(grep docker /proc/mounts | awk '{print $2}')
  if [[ $mounts != "" ]]; then
    umount $mounts
  fi
  pids=$(grep docker /proc/*/mountinfo | awk -F/ '{print $3}' | sort -u)
  if [[ $pids != "" ]]; then
    kill -9 $pids
  fi
  [[ -h /dev/mapper/docker-thinpool ]] && while true; do dmsetup remove docker-thinpool && break; sleep 1; done
  [[ -h /dev/mapper/docker-thinpool_tdata ]] && while true; do dmsetup remove docker-thinpool_tdata && break; sleep 1; done
  [[ -h /dev/mapper/docker-thinpool_tmeta ]] && while true; do dmsetup remove docker-thinpool_tmeta && break; sleep 1; done
  lvdisplay docker/thinpool >/dev/null 2>&1 && while true; do lvremove docker/thinpool && break; sleep 1; done
  vgdisplay docker >/dev/null 2>&1 && while true; do vgremove docker && break; sleep 1; done
  pvdisplay /dev/nvme1n1 >/dev/null 2>&1 && while true; do pvremove /dev/nvme1n1 && break; sleep 1; done
  dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=100

  cp -f /etc/cloudera-scm-agent/config.ini.original /etc/cloudera-scm-agent/config.ini

  rm -rf /var/lib/pgsql/10/data/* /var/lib/pgsql/10/initdb.log /var/kerberos/krb5kdc/* /var/lib/{accumulo,cdsw,cloudera-host-monitor,cloudera-scm-agent,cloudera-scm-eventserver,cloudera-scm-server,cloudera-service-monitor,cruise_control,druid,flink,hadoop-hdfs,hadoop-httpfs,hadoop-kms,hadoop-mapreduce,hadoop-yarn,hbase,hive,impala,kafka,knox,kudu,livy,nifi,nifiregistry,nifitoolkit,oozie,phoenix,ranger,rangerraz,schemaregistry,shellinabox,solr,solr-infra,spark,sqoop,streams_messaging_manager,streams_replication_manager,superset,yarn-ce,zeppelin,zookeeper}/* /var/log/{atlas,catalogd,cdsw,cloudera-scm-agent,cloudera-scm-alertpublisher,cloudera-scm-eventserver,cloudera-scm-firehose,cloudera-scm-server,cruisecontrol,flink,hadoop-hdfs,hadoop-httpfs,hadoop-mapreduce,hadoop-yarn,hbase,hive,httpd,hue,hue-httpd,impalad,impala-minidumps,kafka,kudu,livy,nifi,nifiregistry,nifi-registry,oozie,schemaregistry,solr-infra,spark,statestore,streams-messaging-manager,yarn,zeppelin,zookeeper}/* /kudu/*/* /dfs/*/* /var/local/kafka/data/* /var/{lib,run}/docker/* /var/run/cloudera-scm-agent/process/*
}
