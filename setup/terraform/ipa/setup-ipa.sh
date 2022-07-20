#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail
set -o xtrace
trap 'echo Setup return code: $?' 0
BASE_DIR=$(cd $(dirname $0); pwd -L)

THE_PWD=supersecret1

KEYTABS_DIR=/keytabs
REALM_NAME=WORKSHOP.COM
IPA_ADMIN_PASSWORD=$THE_PWD
DIRECTORY_MANAGER_PASSWORD=$THE_PWD
CM_PRINCIPAL_PASSWORD=$THE_PWD
USER_PASSWORD=$THE_PWD

CM_PRINCIPAL=cloudera-scm

USERS_GROUP=cdp-users
ADMINS_GROUP=cdp-admins

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

function get_group_id() {
  local group=$1
  ipa group-find --group-name="$group" | grep GID | awk '{print $2}'
}

function add_groups() {
  while [[ $# -gt 0 ]]; do
    group=$1
    shift 1
    ipa group-add "$group" || true
  done
}

function add_user() {
  local princ=$1
  local homedir=$2
  shift 2

  # Add user, set password and get keytab
  if ipa user-show "$princ" >/dev/null 2>&1; then
    echo "-- User [$princ] already exists"
  else
    echo "-- Creating user [$princ]"
    USERS_GRP_ID=$(get_group_id $USERS_GROUP)
    echo clouderatemp | ipa user-add "$princ" --first="$princ" --last="User" --cn="$princ" --homedir="$homedir" --noprivate --gidnumber $USERS_GRP_ID --password || true
    ipa group-add-member "$USERS_GROUP" --users="$princ" || true
    kadmin.local change_password -pw ${USER_PASSWORD} $princ
  fi
  mkdir -p "${KEYTABS_DIR}"
  echo -e "${USER_PASSWORD}\n${USER_PASSWORD}" | ipa-getkeytab -p "$princ" -k "${KEYTABS_DIR}/${princ}.keytab" --password
  chmod 444 "${KEYTABS_DIR}/${princ}.keytab"

  # Create a jaas.conf file
  cat > ${KEYTABS_DIR}/jaas-${princ}.conf <<EOF
KafkaClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab="${KEYTABS_DIR}/${princ}.keytab"
  principal="${princ}@${REALM_NAME}";
};
EOF

  # Add user to groups
  while [[ $# -gt 0 ]]; do
    group=$1
    shift 1
    ipa group-add-member "$group" --users="$princ" || true
  done
}

# Set hostname
export PRIVATE_IP=$(hostname -I | awk '{print $1}')
export LOCAL_HOSTNAME=$(hostname -f)
export PUBLIC_IP=$(curl -s http://ifconfig.me || curl -s http://api.ipify.org/)
export PUBLIC_DNS=ipa.${PUBLIC_IP}.nip.io

sed -i.bak "/${LOCAL_HOSTNAME}/d;/^${PRIVATE_IP}/d;/^::1/d" /etc/hosts
echo "$PRIVATE_IP $PUBLIC_DNS $LOCAL_HOSTNAME" >> /etc/hosts

sed -i.bak '/kernel.domainname/d' /etc/sysctl.conf
echo "kernel.domainname=${PUBLIC_DNS#*.}" >> /etc/sysctl.conf
sysctl -p

hostnamectl set-hostname $PUBLIC_DNS
if [[ -f /etc/sysconfig/network ]]; then
  sed -i "/HOSTNAME=/ d" /etc/sysconfig/network
fi
echo "HOSTNAME=${PUBLIC_DNS}" >> /etc/sysconfig/network

# Server install
yum erase -y epel-release || true; rm -f /etc/yum.repos.r/epel* || true
yum_install epel-release
# The EPEL repo has intermittent refresh issues that cause errors like the one below.
# Switch to baseurl to avoid those issues when using the metalink option.
# Error: https://.../repomd.xml: [Errno -1] repomd.xml does not match metalink for epel
sed -i 's/metalink=/#metalink=/;s/#*baseurl=/baseurl=/' /etc/yum.repos.d/epel*.repo
yum_install cowsay figlet ipa-server rng-tools
yum -y upgrade nss-tools
systemctl restart dbus
ipa-server-install --hostname=$(hostname -f) -r $REALM_NAME -n $(hostname -d) -a "$IPA_ADMIN_PASSWORD" -p "$DIRECTORY_MANAGER_PASSWORD" -U

# authenticate as admin
echo "${IPA_ADMIN_PASSWORD}" | kinit admin >/dev/null

# create groups
add_groups $USERS_GROUP $ADMINS_GROUP shadow supergroup

# create CM principal user and add to admins group
add_user admin /home/admin admins $ADMINS_GROUP "trust admins" shadow supergroup

kinit -kt "${KEYTABS_DIR}/admin.keytab" admin
ipa krbtpolicy-mod --maxlife=3600 --maxrenew=604800 || true

# Add LDAP bind user
add_user ldap_bind_user /home/ldap_bind_user

# Add users
add_user workshop /home/workshop $USERS_GROUP
add_user alice /home/alice $USERS_GROUP
add_user bob /home/bob $USERS_GROUP

# Add this role to avoid racing conditions between multiple CMs coming up at the same time
ipa role-add cmadminrole
ipa role-add-privilege cmadminrole --privileges="Service Administrators"

systemctl restart krb5kdc
systemctl enable ipa

# configure and start rng-tools
grep rdrand /proc/cpuinfo || echo 'EXTRAOPTIONS="-r /dev/urandom"' >> /etc/sysconfig/rngd
systemctl start rngd

# Ensure that selinux is turned off now and at reboot
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# Make keytabs and CA cert available through the web server
ln -s /keytabs /var/www/html/keytabs
ln -s /etc/ipa/ca.crt /var/www/html/ca.crt

figlet -f small -w 300  "IPA server deployed successfully"'!' | cowsay -n -f "$(ls -1 /usr/share/cowsay | grep "\.cow" | sed 's/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
echo "Completed successfully: IPA"
