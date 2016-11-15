$:.unshift(File.dirname(__FILE__))

require 'yaml'
require 'log4r'
require 'octokit'
require 'git'
require 'erb'
require 'netrc'
require 'http'
require "graphql/client"
require "graphql/client/http"
require 'net/http'
require 'active_support'
require 'open3'

require 'thumbs/general_helpers'
require 'thumbs/webhook_helpers'
require 'thumbs/pull_request_worker'


module Thumbs
  module GitHub
    def self.dump(file)
      GraphQL::Client.dump_schema(Thumbs::GitHub::HTTP, file)
    end

    def self.load(file)
      GraphQL::Client.load_schema(file)
    end

    HTTP = GraphQL::Client::HTTP.new("https://api.github.com/graphql") do
      def headers(context)
        {
            "Authorization" => "Bearer #{ENV['GITHUB_ACCESS_TOKEN']}"
        }
      end
    end
    file=File.join(File.dirname(__FILE__), '..', 'schema.json')
    dump(file) unless File.exists?(file)

    Schema = load(file)
    Client = GraphQL::Client.new(
        schema: Schema,
        execute: HTTP
    )

  end
end

module Thumbs
  def self.start_logger
    logger  = Log4r::Logger.new 'Thumbs'
    outputter = Log4r::Outputter.stdout
    outputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %m")
    logger.outputters << outputter
  end
end

