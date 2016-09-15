$:.unshift(File.dirname(__FILE__))
require 'bundler'
Bundler.require

require './app'

require 'log4r'
logger  = Log4r::Logger.new 'Thumbs'
logger.outputters << Log4r::Outputter.stderr

file = Log4r::FileOutputter.new('app-file', :filename => 'log/thumbs.log')
file.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %m")
logger.outputters << file

run ThumbsWeb
