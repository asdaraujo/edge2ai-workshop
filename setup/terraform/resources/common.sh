#!/bin/bash

KEYTABS_DIR=/keytabs
KAFKA_CLIENT_PROPERTIES=${KEYTABS_DIR}/kafka-client.properties

function is_kerberos_enabled() {
  if [ -d $KEYTABS_DIR ]; then
    echo yes
  else
    echo no
  fi
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
    if [ "$validate_only" == "no" ]; then
      mkdir -p $KEYTABS_DIR
    fi
  else
    ENABLE_KERBEROS=no
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

  if [ "${HAS_SCHEMAREGISTRY:-}" == "1" -o "${HAS_SMM:-}" == "1" -o "${HAS_SRM:-}" == "1" ]; then
    if [ "$(check_vars "$stack_file" \
              CSP_PARCEL_REPO SCHEMAREGISTRY_CSD_URL \
              STREAMS_MESSAGING_MANAGER_CSD_URL \
              STREAMS_REPLICATION_MANAGER_CSD_URL)" != "0" ]; then
      errors=1
    fi
  fi

  if [ "${HAS_NIFI:-}" == "1" ]; then
    if [ "$(check_vars "$stack_file" \
              CFM_NIFICA_CSD_URL CFM_NIFIREG_CSD_URL CFM_NIFI_CSD_URL)" != "0" ]; then
      errors=1
    fi
  fi

  if [ "${HAS_NIFI:-}" == "1" ]; then
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
  if [ -d ${KEYTABS_DIR} ]; then
    kdestroy
    unset KAFKA_OPTS
  else
    unset HADOOP_USER_NAME
  fi
}

function add_kerberos_principal() {
  local princ=$1
  local username=${princ%%/*}
  username=${username%%@*}
  if [ "$(getent passwd $username > /dev/null && echo exists || echo does_not_exist)" == "does_not_exist" ]; then
    useradd -U $username
  fi
  (sleep 1 && echo -e "supersecret1\nsupersecret1") | /usr/sbin/kadmin.local -q "addprinc $princ"
  mkdir -p ${KEYTABS_DIR}
  echo -e "addent -password -p $princ -k 0 -e aes256-cts\nsupersecret1\nwrite_kt ${KEYTABS_DIR}/$username.keytab" | ktutil
  chmod 444 ${KEYTABS_DIR}/$username.keytab
}

function install_kerberos() {
  krb_server=$(hostname -f)
  krb_realm=WORKSHOP.COM
  krb_realm_lc=$( echo $krb_realm | tr A-Z a-z )

  # Install Kerberos packages
  yum -y install krb5-libs krb5-server krb5-workstation

  # Ensure entropy
  yum -y install rng-tools
  systemctl start rngd
  cat /proc/sys/kernel/random/entropy_avail

  # Update krb5.conf
  replace_pattern="s/kerberos.example.com/$krb_server/g;s/EXAMPLE.COM/$krb_realm/g;s/example.com/$krb_realm_lc/g;s/^#\(.*[={}]\)/\1/;/KEYRING/ d"
  sed -i.bak "$replace_pattern" /etc/krb5.conf
  ls -l /etc/krb5.conf /etc/krb5.conf.bak
  diff  /etc/krb5.conf /etc/krb5.conf.bak || true

  # Update kdc.conf
  replace_pattern="s/EXAMPLE.COM = {/$krb_realm = {\n  max_renewable_life = 7d 0h 0m 0s/"
  sed -i.bak "$replace_pattern" /var/kerberos/krb5kdc/kdc.conf
  ls -l /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.bak
  diff  /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.bak || true

  # Create database
  /usr/sbin/kdb5_util create -s -P supersecret1

  # Update kadm5.acl
  replace_pattern="s/kerberos.example.com/$krb_server/g;s/EXAMPLE.COM/$krb_realm/g;s/example.com/$krb_realm_lc/g;"
  sed -i.bak "$replace_pattern" /var/kerberos/krb5kdc/kadm5.acl
  ls -l /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.bak
  diff /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.bak || true

  # Create CM principal
  add_kerberos_principal scm/admin

  # Set maxrenewlife for krbtgt
  # IMPORTANT: You must explicitly set this, even if the default is already set correctly.
  #            Failing to do so will cause some services to fail.

  kadmin.local -q "modprinc -maxrenewlife 7day krbtgt/$krb_realm@$krb_realm"

  # Start Kerberos
  systemctl enable krb5kdc
  systemctl enable kadmin
  systemctl start krb5kdc
  systemctl start kadmin

  # Add principals
  add_kerberos_principal hdfs
  add_kerberos_principal yarn
  add_kerberos_principal kafka
  add_kerberos_principal flink

  add_kerberos_principal workshop
  add_kerberos_principal admin
  add_kerberos_principal alice
  add_kerberos_principal bob

  # Create a client properties file for Kafka clients
  cat >> ${KAFKA_CLIENT_PROPERTIES} <<EOF
security.protocol=SASL_PLAINTEXT
sasl.kerberos.service.name=kafka
EOF

  # Create a jaas.conf file
  cat >> ${KEYTABS_DIR}/jaas.conf <<EOF
KafkaClient {
com.sun.security.auth.module.Krb5LoginModule required
useTicketCache=true;
};
EOF

}
