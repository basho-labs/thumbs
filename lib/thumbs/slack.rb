
module Thumbs
  module Slack
    def add_slack_message(channel, message)
      client = Slack::RealTime::Client.new

      rc = HTTP.post("https://slack.com/api/chat.postMessage", params: {
          token: ENV['SLACK_API_TOKEN'],
          channel: channel,
          text: message,
          as_user: true
      })
    end
  end
end
