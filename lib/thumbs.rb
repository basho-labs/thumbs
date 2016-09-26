$:.unshift(File.dirname(__FILE__))

require 'yaml'
require 'log4r'
require 'octokit'
require 'git'
require 'erb'
require 'netrc'
require 'http'


require 'thumbs/general_helpers'
require 'thumbs/webhook_helpers'
require 'thumbs/pull_request_worker'


module Thumbs
  def self.start_logger
    logger  = Log4r::Logger.new 'Thumbs'
    outputter = Log4r::Outputter.stdout
    outputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %m")
    logger.outputters << outputter
  end
end

