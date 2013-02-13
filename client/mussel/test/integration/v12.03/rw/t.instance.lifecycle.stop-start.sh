#!/bin/bash
#
# requires:
#   bash
#

## include files

. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh

## variables

## functions

###

function test_stop_instance() {
  # :state: stopping
  # :status: online
  run_cmd ${namespace} stop ${instance_uuid} >/dev/null
  assertEquals $? 0

  # :state: stopped
  # :status: online
  retry_until "check_document_pair ${namespace} ${instance_uuid} state stopped"
  assertEquals $? 0
}

function test_start_instance() {
  # :state: initializing
  # :status: online
  run_cmd ${namespace} start ${instance_uuid} >/dev/null
  assertEquals $? 0

  # :state: running
  # :status: online
  retry_until "check_document_pair ${namespace} ${instance_uuid} state running"
  assertEquals $? 0
}

## shunit2

. ${shunit2_file}
