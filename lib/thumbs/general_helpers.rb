require 'sinatra/base'

module Sinatra
  module GeneralHelpers
    def debug_message(message)
      log = Log4r::Logger['Thumbs']
      ((log && log.respond_to?(:debug)) ? log.debug(message) : nil )
    end

    def authenticate_github
      Octokit::Client.new(:netrc => true)
    end
  end
end
