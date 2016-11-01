
unit_tests do

  include Sinatra::GeneralHelpers
  include Sinatra::WebhookHelpers

  test "new pr payload_type" do
    new_pr_payload = {
        'action' => 'opened',
        'repository' => {'full_name' => "org/user"},
        'number' => 1,
        'pull_request' => {'number' => 1, 'body' => "awesome pr"}
    }
    assert new_pr_payload['action'] == 'opened'

    assert payload_type(new_pr_payload) == :new_pr, payload_type(new_pr_payload).to_s
  end

  test "can detect unregistered payload type" do

    strange_payload = {
        'unused' => {'other' => "value"},
        'unrecognized_structure' => {'number' => 34},
        'weird' => {}
    }

    assert payload_type(strange_payload) == :unregistered, payload_type(strange_payload).inspect
  end

  test "can detect new_push payload type" do

    new_push_payload = {
        'action' => 'synchronize'
    }

    assert payload_type(new_push_payload) == :new_push, payload_type(new_push_payload).to_s
  end

  test "can detect new comment payload type" do
    new_comment_payload = {
        'repository' => {'full_name' => "org/user"},
        'issue' => {'number' => 1,
                    'pull_request' => {'number' => 1}
        },
        'comment' => {'body' => "foo", 'user' => { 'login' => 'foo'}}
    }

    assert payload_type(new_comment_payload) == :new_comment

  end

  test "can detect new base payload type" do
    new_base_payload = {
        'action' => 'edited',
        'changes' => {
            'base' => {
                'ref' => {
                  'from' => 'master'
                },
                'sha' => {
                  'from' => 'afadb0afefe87362ca819a4a78b5bc89dede3133'
                }
            }
        }
    }

    assert payload_type(new_base_payload) == :new_base, payload_type(new_base_payload).to_s
  end

  test "can detect merged base payload type" do
    merged_base_payload = {

        'ref' => 'refs/heads/master',
        'before' => 'e65bc8ef21630b917ca9ecc62adb3b17c1cbe2ef',
        'after' => '34ae62fe74815d254b78c5b1c57979dd8b9e4de5',
        'commits' => [],
        'head_commit' => {},
        'pusher' => { 'name' => 'thumbot',
                      'email' => 'git.thumbs@gmail.com'},
        'repository' => {'full_name' => 'org/user' }
    }

    assert payload_type(merged_base_payload) == :merged_base, payload_type(merged_base_payload).to_s
  end

  test "can detect new approal  payload type" do
    new_approval_base_payload = { 'approval' => 'yes'}

    assert payload_type(merged_base_payload) == :merged_base, payload_type(merged_base_payload).to_s
  end
end
