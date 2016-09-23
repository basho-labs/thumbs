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
    logger.outputters << Log4r::Outputter.stderr
    file = Log4r::FileOutputter.new('app-file', :filename => 'log/thumbs.log')
    file.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %m")
    logger.outputters << file
  end
end

