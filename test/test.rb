$:.unshift(File.dirname(__FILE__))
$:.unshift(File.join(File.dirname(__FILE__), '/../'))

ENV['RACK_ENV'] = 'test'
#
require 'test/test_helper'
require 'test/test_docker'
require 'test/test_build_steps'
require 'test/test_webhook'
require 'test/test_payload'
require 'test/test_persisted_build_status'
require 'test/test_state'
require 'test/test_common'
require 'test/test_code_approvals'
require 'test/test_merge'
