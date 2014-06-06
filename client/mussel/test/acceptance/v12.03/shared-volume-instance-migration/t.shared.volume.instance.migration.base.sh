#!/bin/bash
#
#
#
#

## include files

. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh

## variables
launch_host_node=${launch_host_node:-hn-dsv0003}
migration_host_node=${migration_host_node:-hn-dsv0005}
blank_volume_size=${blank_volume_size:-10}

## hook functions

last_result_path=""

function setUp() {
  last_result_path=$(mktemp --tmpdir=${SHUNIT_TMPDIR})

  # reset command parameters
  volumes_args=
}

### step

# API test for shared volume instance migration.
#
# 1.  boot shared volume instance.
# 2.  migration the instance.
# 3.  check the process.
# 4.  poweroff the instance.
# 5.  poweron the instance.
# 6.  attach volume to instance.
# 7.  check the attach second volume.
# 8.  detach volume to instance.
# 9.  check the detach second volume.
# 10. terminate the instance.
function test_migration_shared_volume_instance(){
  # boot shared volume instance.
  local host_node_id=${launch_host_node}
  create_instance

  # migration the instance.
  host_node_id=${migration_host_node} run_cmd instance move ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # check the process.

  # poweroff the instance.
  run_cmd instance poweroff ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state halted"
  assertEquals 0 $?

  # poweron the instance.
  run_cmd instance poweron ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # wait for network to be ready
  wait_for_network_to_be_ready ${instance_ipaddr}

  # wait for sshd to be ready
  wait_for_sshd_to_be_ready    ${instance_ipaddr}

  # create new blank volume
  volume_uuid=$(volume_size=${blank_volume_size} run_cmd volume create | hash_value uuid)
  retry_until "document_pair? volume ${volume_uuid} state available"
  assertEquals 0 $?

  # attach volume to instance.
  instance_id=${instance_uuid} run_cmd volume attach ${volume_uuid}
  retry_until "document_pair? volume ${volume_uuid} state attached"
  assertEquals 0 $?

  # check the attach second volume.
  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} lsblk
	EOS
  assertEquals 0 $?

  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} ls -la /dev/mapper/
	EOS
  assertEquals 0 $?

  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} ls -la /dev/disk
	EOS
  assertEquals 0 $?

  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} ls -la /dev/disk/by-label/
	EOS
  assertEquals 0 $?

  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} ls -la /dev/disk/by-path/
	EOS
  assertEquals 0 $?

  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	${remote_sudo} ls -la /dev/disk/by-uuid/
	EOS
  assertEquals 0 $?

  # detach volume to instance
  instance_id=${instance_uuid} run_cmd volume detach ${volume_uuid}
  retry_until "document_pair? volume ${volume_uuid} state available"
  assertEquals 0 $?

  # check the detach second volume.

  # delete new blank volume
  run_cmd volume destroy ${volume_uuid}
  retry_until "document_pair? volume ${volume_uuid} state deleted"
  assertEquals 0 $?

  # terminate the instance.
  run_cmd instance destroy ${instance_uuid} >/dev/null
  assertEquals 0 $?
}

# API test for shared volume instance with second blank volume migration.
#
# 1. boot shared volume instance with second blank volume.
# 2. migration the instance.
# 3. check the process.
# 4. check the second blank disk.
# 5. poweroff the instance.
# 6. poweron the instance.
# 7. terminate the instance.
function test_migration_shared_volume_instance_with_second_blank_volume(){
  # boot shared volume instance with second blank volume.
  volumes_args="volumes[0][size]=${blank_volume_size} volumes[0][volume_type]=shared"
  local host_node_id=${launch_host_node}
  create_instance

  # migration the instance.
  host_node_id=${migration_host_node} run_cmd instance move ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # check the process.

  # check the second blank disk.

  # poweroff the instance.
  run_cmd instance poweroff ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state halted"
  assertEquals 0 $?

  # poweron the instance.
  run_cmd instance poweron ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # terminate the instance.
  run_cmd instance destroy ${instance_uuid} >/dev/null
  assertEquals 0 $?
}

## shunit2

. ${shunit2_file}

