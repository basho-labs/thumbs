class WebhookTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Thumbs

  def app
    ThumbsWeb
  end


  def test_can_access_repo

    cassette(:simple_repo) do
      repository = Octokit.repo 'thumbot/prtester'
      assert_not_nil repository
      assert_equal 'prtester', repository.name
    end

  end

  def test_can_get_pr

    cassette(:get_basic_pr) do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert !prw.nil?
      assert prw.kind_of?(Thumbs::PullRequestWorker)
      assert_equal "thumbot/prtester", prw.pr.base.repo.full_name
      assert_equal "thumbot/prtester", prw.repo
      assert_equal TESTPR, prw.pr.number
    end

  end

  def test_can_get_status
    cassette(:get_ratelimit) do
      get '/status'
      assert last_response.body.include?("<pre>"), last_response.body
      last_response_yaml=last_response.body.gsub!(/(\<pre\>|\<\/pre\>)/, '')
      status_hash=YAML.load(last_response_yaml)
      assert status_hash.key?(:status), status_hash.inspect
      assert status_hash.key?(:version)
      assert status_hash.key?(:rate_limit)
    end
  end

  def test_new_push_hook

  end

  def test_new_base_hook
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)

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
          },
          'repository' => {'full_name' => prw.repo },
          'pull_request' => {'number' => prw.pr.number, 'body' => prw.pr.body }
      }
      cassette(:get_comments, :record => :all) do
        cassette(:get_issue_comments, :record => :new_episodes) do

          cassette(:post_webhook_new_base, :record => :new_episodes) do

            post '/webhook', new_base_payload.to_json do
              assert last_response.body.include?("OK"), last_response.body

            end
          end
        end
      end


    end
  end

  def test_new_comment_hook

  end
  def test_merged_pr_hook
      default_vcr_state do
        prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)

        merged_pr_payload = {

            'refs' => 'refs/heads/master',
            'before' => 'e65bc8ef21630b917ca9ecc62adb3b17c1cbe2ef',
            'after' => '34ae62fe74815d254b78c5b1c57979dd8b9e4de5',
            'commits' => [],
            'head_commit' => {},
            'pusher' => { 'name' => 'thumbot',
                          'email' => 'git.thumbs@gmail.com'},
            'repository' => {'full_name' => prw.repo }
        }
        cassette(:get_comments, :record => :all) do
          cassette(:get_issue_comments, :record => :new_episodes) do
            cassette(:post_webhook_merged_pr, :record => :new_episodes) do
              post '/webhook', merged_pr_payload.to_json do
                assert last_response.body.include?("OK"), last_response.body
              end
            end
          end
        end
      end
    end


  def test_new_pr_hook
    cassette(:load_pr, :record => :new_episodes) do
      prw = Thumbs::PullRequestWorker.new(:repo => 'thumbot/prtester', :pr => TESTPR)

      new_pr_webhook_payload = {
          'repository' => {'full_name' => prw.repo},
          'number' => prw.pr.number,
          'pull_request' => {'number' => prw.pr.number, 'body' => prw.pr.body}
      }
      prw.unpersist_build_status
      assert prw.build_status[:steps].keys.length == 1 ,prw.build_status[:steps].inspect
      assert prw.build_status[:steps].key?(:merge)
      remove_comments(prw.repo, prw.pr.number)
      cassette(:get_comments, :record => :all) do
        cassette(:get_issue_comments, :record => :all) do

          cassette(:post_webhook_new_pr, :record => :all) do

            post '/webhook', new_pr_webhook_payload.to_json do
              assert last_response.body.include?("OK"), last_response.body
            end
          end
        end
      end
    end
  end
  def test_new_approval_hook
    cassette(:load_pr, :record => :new_episodes) do
      prw = Thumbs::PullRequestWorker.new(:repo => 'thumbot/prtester', :pr => TESTPR)

      new_approval_webhook_payload = {
          'repository' => {'full_name' => prw.repo},
          'number' => prw.pr.number,
          'pull_request' => {'number' => prw.pr.number, 'body' => prw.pr.body}
      }
      prw.unpersist_build_status

      remove_comments(prw.repo, prw.pr.number)
      cassette(:get_comments, :record => :all) do
        cassette(:get_issue_comments, :record => :all) do

          cassette(:post_webhook_new_approval, :record => :all) do

            post '/webhook', new_approval_webhook_payload.to_json do
              assert last_response.body.include?("OK"), last_response.body
            end
          end
        end
      end
    end
  end
end
