class HelloWorldTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Thumbs

  def app
    ThumbsWeb
  end

  def test_webhook_mergeable_pr_test
    test_pr_worker = create_test_pr("thumbot/prtester")

    assert test_pr_worker.comments.length == 0
    assert test_pr_worker.reviews.length == 0
    assert test_pr_worker.bot_comments.length == 0

    new_pr_webhook_payload = {
        'repository' => {'full_name' => test_pr_worker.repo},
        'number' => test_pr_worker.pr.number,
        'pull_request' => {'number' => test_pr_worker.pr.number, 'body' => test_pr_worker.pr.body}
    }

    post '/webhook', new_pr_webhook_payload.to_json

    assert_true last_response.body.include?("OK"), last_response.body

    assert_true test_pr_worker.open?
    assert test_pr_worker.reviews.length == 0

    assert test_pr_worker.comments.length == 1
    assert test_pr_worker.bot_comments.length == 1
    assert_true test_pr_worker.open?

    assert test_pr_worker.comments.first['body'] =~ /Build Status/

    create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)

    assert test_pr_worker.reviews.length >= 2

    new_comment_payload = {
        'repository' => {'full_name' => test_pr_worker.repo},
        'issue' => {'number' => test_pr_worker.pr.number,
                    'pull_request' => {}
        },
        'comment' => {'body' => "looks good"}
    }

    assert payload_type(new_comment_payload) == :new_comment, payload_type(new_comment_payload).to_s

    post "/webhook", new_comment_payload.to_json

    assert last_response.body.include?("OK"), last_response.body

    assert_false test_pr_worker.open?
    test_pr_worker.close

  end


end
