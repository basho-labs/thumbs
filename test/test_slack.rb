$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'
require 'http'
require 'json'

unit_tests do

  test "can post to slack" do

    client = Slack::RealTime::Client.new


    message="Testing slack integration"

    rc = HTTP.post("https://slack.com/api/chat.postMessage", params: {
        token: ENV['SLACK_API_TOKEN'],
        channel: '#testing',
        text: message,
        as_user: true
    })

    parsed_response = JSON.parse(rc.body)
    assert parsed_response.key?('ok')
    assert parsed_response['ok'] == true
  end


end