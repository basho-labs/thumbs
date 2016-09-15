require 'sinatra/base'

module Sinatra
  module GeneralHelpers
    def debug_message(message)
      log = Log4r::Logger['Thumbs']
      log.debug message
    end

    def authenticate_slack
      Slack.configure do |config|
        config.token = ENV['SLACK_API_TOKEN']
        fail 'Missing ENV[SLACK_API_TOKEN]!' unless config.token
      end
    end

    def authenticate_github
      Octokit::Client.new(:netrc => true)
    end
  end
end
