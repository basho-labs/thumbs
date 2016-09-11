$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'

class HelloWorldTest < Test::Unit::TestCase
  include Rack::Test::Methods

  include Sinatra::GeneralHelpers
  include Sinatra::WebhookHelpers
  def app
    ThumbsWeb
  end

  def test_can_detect_payload_type
    strange_payload = {
        'unused' => {'other' => "value"},
        'unrecognized_structure' => {'number' => 34},
        'weird' => {}
    }

    assert payload_type(strange_payload) == :unregistered

    repo = "org/user"
    pr = 1

    new_pr_payload = {
        'repository' => {'full_name' => repo},
        'number' => 1,
        'pull_request' => {'number' => 1, 'body' => "cool pr"}
    }
    assert new_pr_payload['pull_request']

    assert payload_type(new_pr_payload) == :new_pr, payload_type(new_pr_payload).to_s


    new_comment_payload = {
        'repository' => {'full_name' => repo},
        'issue' => {'number' => pr,
                    'pull_request' => {'number' => pr}
        },
        'comment' => {'body' => "foo"}
    }

    assert payload_type(new_comment_payload) == :new_comment

  end

  def test_payload_type
    new_pr_payload = {
        'repository' => {'full_name' => "org/user"},
        'number' => 1,
        'pull_request' => {'number' => 1, 'body' => "awesome pr"}
    }

    assert payload_type(new_pr_payload) == :new_pr, payload_type(new_pr_payload).to_s
  end



end

#use ```shell for output display