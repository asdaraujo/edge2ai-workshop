#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail
set -o xtrace
trap 'echo Setup return code: $?' 0
BASE_DIR=$(cd $(dirname $0); pwd -L)

THE_PWD=Supersecret1

KEYTABS_DIR=/keytabs
REALM_NAME=WORKSHOP.COM
IPA_ADMIN_PASSWORD=$THE_PWD
DIRECTORY_MANAGER_PASSWORD=$THE_PWD
CM_PRINCIPAL_PASSWORD=$THE_PWD
USER_PASSWORD=$THE_PWD

CM_PRINCIPAL=cloudera-scm

USERS_GROUP=cdp-users
ADMINS_GROUP=cdp-admins

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
    local gid=$(get_group_id $1)
    echo clouderatemp | ipa user-add "$princ" --first="$princ" --last="User" --cn="$princ" --homedir="$homedir" --noprivate --gidnumber $gid --password || true
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

log_status "Setting host and domain names"
export PRIVATE_IP=$(hostname -I | awk '{print $1}')
export LOCAL_HOSTNAME=$(hostname -f)
export PUBLIC_IP=$(curl -4sL http://ifconfig.me || curl -4sL http://api.ipify.org/ || curl -4sL https://ipinfo.io/ip)
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

if [[ $(get_os_type) == "RHEL" ]]; then
  log_status "Disable RHEL Subscription Manager"
  sed -i.bak 's/^ *enabled=.*/enabled=0/' /etc/yum/pluginconf.d/subscription-manager.conf
fi

log_status "Installing IPA server"
yum erase -y epel-release || true; rm -f /etc/yum.repos.r/epel* || true
install_epel

log_status "Installing needed tools"
yum_install cowsay figlet rng-tools rsync nss-tools
yum -y upgrade nss-tools # Update nss-tools in case it had been previously installed
systemctl restart dbus
if [[ $(get_os_major_version) == "8" ]]; then
  sudo yum -y install @idm:DL1
  sudo yum -y install freeipa-server ipa-server-dns bind-dyndb-ldap
else
  yum_install ipa-server
fi

log_status "Installing IPA server"
ipa-server-install --hostname=$(hostname -f) -r $REALM_NAME -n $(hostname -d) -a "$IPA_ADMIN_PASSWORD" -p "$DIRECTORY_MANAGER_PASSWORD" -U

# authenticate as admin
echo "${IPA_ADMIN_PASSWORD}" | kinit admin >/dev/null

log_status "Creating groups"
add_groups $USERS_GROUP $ADMINS_GROUP shadow supergroup hue

log_status "Creating Cloudera Manager principal user and adding it to admins group"
add_user admin /home/admin admins $ADMINS_GROUP $USERS_GROUP "trust admins" shadow supergroup

kinit -kt "${KEYTABS_DIR}/admin.keytab" admin
ipa krbtpolicy-mod --maxlife=84600 --maxrenew=604800 || true

log_status "Creating LDAP bind user"
add_user ldap_bind_user /home/ldap_bind_user $USERS_GROUP

log_status "Creating HUE proxy user"
add_user hue /home/hue hue $USERS_GROUP

log_status "Creating other users"
add_user workshop /home/workshop $USERS_GROUP
add_user alice /home/alice $USERS_GROUP
add_user bob /home/bob $USERS_GROUP

log_status "Adding required roles"
# Add this role to avoid racing conditions between multiple CMs coming up at the same time
ipa role-add cmadminrole
ipa role-add-privilege cmadminrole --privileges="Service Administrators"

log_status "Starting the IPA service"
systemctl restart krb5kdc
systemctl enable ipa

log_status "Configuring and starting rng-tools"
grep rdrand /proc/cpuinfo || echo 'EXTRAOPTIONS="-r /dev/urandom"' >> /etc/sysconfig/rngd
systemctl start rngd

log_status "Ensuring that SElinux is turned off now and at reboot"
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

log_status "Making keytabs and CA cert available through the web server"
systemctl stop httpd # Stop web server temporarily; it will be restarted upon reboot
ln -s /keytabs /var/www/html/keytabs
ln -s /etc/ipa/ca.crt /var/www/html/ca.crt

figlet -f small -w 300  "IPA server deployed successfully"'!' | /usr/bin/cowsay -n -f "$(find /usr/share/cowsay -type f -name "*.cow" | grep "\.cow" | sed 's#.*/##;s/\.cow//' | egrep -v "bong|head-in|sodomized|telebears" | shuf -n 1)"
echo "Completed successfully: IPA"
log_status "IPA server installed successfully."

log_status "Rebooting IPA server to finish setup."
sleep 20 # Wait a few seconds for check-setup-status to pickup the rebooting message
nohup bash -c "sleep 3; reboot" & # Reboot from within a nohup so that the script can exit cleanly
