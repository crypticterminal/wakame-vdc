#!/bin/bash
#
#
#

## include files
. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh

## variables
blank_volume_size=${blank_volume_size:-10}

## functions
last_result_path=""

function setUp() {
  last_result_path=$(mktemp --tmpdir=${SHUNIT_TMPDIR})

  # reset command parameters
  volumes_args=
}

## instance
function before_create_instance() {
  # boot instance with second blank volume.
  if is_container_hypervisor; then
    volumes_args="volumes[0][size]=${blank_volume_size} volumes[0][volume_type]=shared volumes[0][guest_device_name]=/dev/vdc"
  else
    volumes_args="volumes[0][size]=${blank_volume_size} volumes[0][volume_type]=shared"
  fi
}

## step
function test_image_backup_just_for_boot_volume() {
  # poweroff instance
  run_cmd instance poweroff ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state halted"
  assertEquals 0 $?

  run_cmd instance show_volumes ${instance_uuid} | ydump > $last_result_path
  assertEquals 0 $?

  local ex_volume_uuid=$(yfind '1/:uuid:' < $last_result_path)
  test -n "$ex_volume_uuid"
  assertEquals 0 $?

  # instance backup
  run_cmd instance backup ${instance_uuid} | ydump > $last_result_path
  assertEquals 0 $?

  local image_uuid=$(yfind ':image_id:' < $last_result_path)
  test -n "$image_uuid"
  assertEquals 0 $?

  local backup_object_uuid=$(yfind ':backup_object_id:' < $last_result_path)
  test -n "$backup_object_uuid"
  assertEquals 0 $?

  # assert that poweron should fail until backup task completes.
  run_cmd instance poweron ${instance_uuid} >/dev/null
  assertNotEquals 0 $?

  retry_until "document_pair? image ${image_uuid} state available"
  assertEquals 0 $?

  # delete image
  run_cmd image destroy ${image_uuid}
  assertEquals 0 $?

  # delete backup object
  run_cmd backup_object destroy ${backup_object_uuid}
  assertEquals 0 $?

  # poweron instance
  run_cmd instance poweron ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # wait for network to be ready
  wait_for_network_to_be_ready ${instance_ipaddr}

  # wait for sshd to be ready
  wait_for_sshd_to_be_ready    ${instance_ipaddr}
}

function test_image_backup_just_for_boot_volume_and_second_blank_volume() {
  # poweroff instance
  run_cmd instance poweroff ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state halted"
  assertEquals 0 $?

  run_cmd instance show_volumes ${instance_uuid} | ydump > $last_result_path
  assertEquals 0 $?

  local ex_volume_uuid=$(yfind '1/:uuid:' < $last_result_path)
  test -n "$ex_volume_uuid"
  assertEquals 0 $?

  # instance backup
  all=true run_cmd instance backup ${instance_uuid} | ydump > $last_result_path
  assertEquals 0 $?

  local image_uuid=$(yfind ':image_id:' < $last_result_path)
  test -n "$image_uuid"
  assertEquals 0 $?

  local backup_object_uuid=$(yfind ':backup_object_id:' < $last_result_path)
  test -n "$backup_object_uuid"
  assertEquals 0 $?

  # assert that poweron should fail until backup task completes.
  run_cmd instance poweron ${instance_uuid} >/dev/null
  assertNotEquals 0 $?

  retry_until "document_pair? image ${image_uuid} state available"
  assertEquals 0 $?

  # delete image
  run_cmd image destroy ${image_uuid}
  assertEquals 0 $?

  # delete backup object
  run_cmd backup_object destroy ${backup_object_uuid}
  assertEquals 0 $?

  # poweron instance
  run_cmd instance poweron ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state running"
  assertEquals 0 $?

  # wait for network to be ready
  wait_for_network_to_be_ready ${instance_ipaddr}

  # wait for sshd to be ready
  wait_for_sshd_to_be_ready    ${instance_ipaddr}
}

## shunit2
. ${shunit2_file}

