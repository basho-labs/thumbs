$:.unshift(File.dirname(__FILE__))
require 'bundler'
Bundler.require

require './app'

Thumbs.start_logger

run ThumbsWeb
