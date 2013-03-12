#!/bin/bash
#
# requires:
#   bash
#

## include files

## variables

declare instance_uuid

### required

image_id=${image_id:-wmi-centos1d}
hypervisor=${hypervisor:-openvz}
cpu_cores=${cpu_cores:-1}
memory_size=${memory_size:-256}
vifs=
ssh_key_id=

### ssh_key_pair

ssh_key_pair_path=${ssh_key_pair_path:-${BASH_SOURCE[0]%/*}/key_pair.$$}
ssh_key_pair_uuid=
public_key=${ssh_key_pair_path}.pub

## functions

### instance

function _create_instance() {
  create_ssh_key_pair

  local create_output="$(run_cmd instance create)"
  echo "${create_output}"

  instance_uuid=$(echo "${create_output}" | hash_value id)
  retry_until "document_pair? instance ${instance_uuid} state running"
}

function _destroy_instance() {
  run_cmd instance destroy ${instance_uuid}
  retry_until "document_pair? instance ${instance_uuid} state terminated"

  destroy_ssh_key_pair
}

### ssh_key_pair

function create_ssh_key_pair() {
  generate_ssh_keypair ${ssh_key_pair_path}

  local create_output="$(run_cmd ssh_key_pair create)"
  echo "${create_output}"

  ssh_key_pair_uuid=$(echo "${create_output}" | hash_value id)
  ssh_key_id=${ssh_key_pair_uuid}
}

function destroy_ssh_key_pair() {
  run_cmd ssh_key_pair destroy ${ssh_key_pair_uuid}
  rm -f ${ssh_key_pair_path}*
}

#### instance hooks

function  before_create_instance() { :; }
function   after_create_instance() { :; }
function before_destroy_instance() { :; }
function  after_destroy_instance() { :; }

function create_instance() {
  before_create_instance
        _create_instance
   after_create_instance
}
function destroy_instance() {
  before_destroy_instance
        _destroy_instance
   after_destroy_instance
}
