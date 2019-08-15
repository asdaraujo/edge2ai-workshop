#!/bin/bash

export TF_VAR_key_name="${TF_VAR_name_prefix}-$(echo -n "$TF_VAR_owner" | base64)"
export TF_VAR_ssh_private_key=${TF_VAR_key_name}.pem
export TF_VAR_ssh_public_key=${TF_VAR_key_name}.pem.pub
export TF_VAR_my_public_ip=$(curl -sL ifconfig.me || curl -sL ipapi.co/ip || curl -sL icanhazip.com)

function log() {
  echo "[$(date)] [$(basename $0): $BASH_LINENO] : $*"
}

function ensure_key_pair() {
  if [ -f ${TF_VAR_ssh_private_key} ]; then
    log "Private key already exists: ${TF_VAR_ssh_private_key}. Will reuse it."
  else
    log "Creating key pair"
    umask 0277
    ssh-keygen -f ${TF_VAR_ssh_private_key} -N "" -m PEM -t rsa -b 2048
    umask 0022
    log "Private key created: ${TF_VAR_ssh_private_key}"
  fi
}

function delete_key_pair() {
  if [ -f ${TF_VAR_ssh_private_key} ]; then
    log "Deleting key pair [${TF_VAR_key_name}]"
    mv -f ${TF_VAR_ssh_private_key} .${TF_VAR_ssh_private_key}.OLD.$(date +%s)
    mv -f ${TF_VAR_ssh_public_key} .${TF_VAR_ssh_public_key}.OLD.$(date +%s)
  fi
}

