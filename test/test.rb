ENV['RACK_ENV'] = 'test'

$:.unshift(File.dirname(__FILE__))

require 'test_helper'

#Pacto.generate!

#contracts = Pacto.load_contracts('contracts/services', 'http://api.github.com')
#contracts.stub_providers

require 'test/test_persisted_build_status'

#require 'test/test_minimal'
#require 'test/test_basic_flow'
#require 'test/test_integrations'
#require 'test/test_webhook'
#require 'test/test_slack'
