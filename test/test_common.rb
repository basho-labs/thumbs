unit_tests do

  test "should be able to generate base and sha specific build guid" do
    default_vcr_state do
      assert PRW.respond_to?(:build_guid)
      assert_equal "#{PRW.pr.base.ref.gsub(/\//, '_')}.#{PRW.pr.base.sha.slice(0, 7)}.#{PRW.pr.head.ref.gsub(/\//, '_')}.#{PRW.most_recent_head_sha.slice(0, 7)}", PRW.build_guid
    end
  end


  test "can get open pull requests for repo" do
    default_vcr_state do
      PRW.respond_to?(:open_pull_requests)
      open_pull_requests = PRW.client.pull_requests(PRW.repo, :state => 'open')
      assert_equal open_pull_requests.collect { |pr| pr[:base][:ref] }, PRW.open_pull_requests.collect { |pr| pr[:base][:ref] }
    end
  end

  test "can get open pull requests for repo and branch" do
    default_vcr_state do
      PRW.respond_to?(:pull_requests_for_base_branch)
      matched_base_pull_requests = PRW.open_pull_requests.collect { |pr| pr if pr.base.ref == "master" }
      assert_equal matched_base_pull_requests.collect { |pr| pr[:base][:ref] }, PRW.pull_requests_for_base_branch("master").collect { |pr| pr[:base][:ref] }
    end
  end

  test "can get commits for branch " do
    default_vcr_state do
      commits = PRW.client.commits(TESTREPO, PRW.pr.head.ref)
      assert_equal PRW.commits.first[:sha], commits.first[:sha]
    end
  end

  test "can provide most recent head sha" do
    # do the most recent head sha from the branch
    default_vcr_state do
      most_recent_head_sha = PRW.client.commits(PRW.repo, PRW.pr.head.ref).first[:sha]
      assert_equal PRW.pr.head.sha, most_recent_head_sha
    end
  end

  test "can provide most recent base sha" do
    # do the most recent base sha from the branch
    default_vcr_state do
      most_recent_base_sha = PRW.client.commits(PRW.repo, PRW.pr.base.ref).first[:sha]
      assert_equal PRW.pr.base.sha, most_recent_base_sha
    end
  end
  test "can provide most recent timestamp " do
    # do the most recent timestamp
    default_vcr_state do
      head_commits=PRW.client.commits(PRW.repo, PRW.pr.head.ref)
      base_commits=PRW.client.commits(PRW.repo, PRW.pr.base.ref)
      most_recent_head_commit_timestamp = DateTime.parse(head_commits.first[:commit][:committer][:date].to_s)
      most_recent_base_commit_timestamp = DateTime.parse(base_commits.first[:commit][:committer][:date].to_s)

      assert most_recent_base_commit_timestamp.kind_of?(DateTime)
      assert most_recent_head_commit_timestamp.kind_of?(DateTime)

      assert most_recent_head_commit_timestamp > most_recent_base_commit_timestamp
      assert_equal most_recent_head_commit_timestamp, PRW.most_recent_commit_timestamp

    end
  end

  test "can add environment variable to config and session" do
    default_vcr_state do
      PRW.thumb_config.delete('env')
      PRW.build_steps=['echo $TEST_ENV']
      PRW.run_build_steps
      status=PRW.build_status[:main][:steps]
      assert status.kind_of?(Hash), status.inspect
      assert status[:"echo_$TEST_ENV"][:output] !=~/testvalue/

      PRW.thumb_config['env'] = {"TEST_ENV" => "testvalue"}
      PRW.run_build_steps
      assert status[:"echo_$TEST_ENV"][:output] =~ /testvalue/
    end
  end

  test "can add shell to config and session" do
    default_vcr_state do
      PRW.thumb_config.delete('env')
      PRW.build_steps=['echo $SHELL']
      PRW.run_build_steps
      status=PRW.build_status[:main][:steps][:"echo_$SHELL"]
      assert status[:output] =~ /\/bin\/bash/, status[:output].inspect
      assert status[:output] !=~/zsh/
      PRW.thumb_config['shell'] = "/bin/bash"
      PRW.run_build_steps
      status=PRW.build_status[:main][:steps][:"echo_$SHELL"]
      assert_equal '/bin/bash', status[:output].strip, status[:output]
    end
  end
  test "can get more than 30 comments" do
    default_vcr_state do
      PRW.respond_to?(:all_comments)
      prw=Thumbs::PullRequestWorker.new(repo: 'davidx/prtester', pr: 321)
      assert prw.all_comments.length > 30
    end
  end

  test "can determine org_member" do
    default_vcr_state do
      ORGPRW.respond_to?(:org_member?)
      assert_false ORGPRW.org_member?('bob')
      assert_true ORGPRW.org_member?('thumbot')
    end
  end

  test "can detect forked repo branch pr" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(repo: 'davidx/prtester', pr: 323)
      assert prw.respond_to?(:forked_repo_branch_pr?)
      assert_true prw.forked_repo_branch_pr?
      assert_false PRW.forked_repo_branch_pr?
    end
  end

  test "should be able to detect @ in wait_lock" do
    cassette(:prmain, :record => :new_episodes) do
      prw = Thumbs::PullRequestWorker.new(repo: 'davidx/prtester', pr: 316)
      assert prw.wait_lock?
    end
  end

  test "should be able to detect wait lock" do
    cassette(:prmain, :record => :new_episodes) do
      prw = Thumbs::PullRequestWorker.new(repo: 'davidx/prtester', pr: 323)
      assert prw.respond_to?(:wait_lock?)

      client2 = Octokit::Client.new(:netrc => true,
                                    :netrc_file => ".netrc.davidpuddy1")
      cassette(:pr, :record => :new_episodes, :record => :all) do

        comment=client2.add_comment(prw.repo, prw.pr.number, "@thumbot wait", options = {})
        sleep 2
        cassette(:refresh, :record => :all) do

          cassette(:get_new_comments, :record => :all) do
            comments=client2.issue_comments(prw.repo, prw.pr.number, per_page: 100)
            assert_true comments.any? { |comment| comment[:body] =~ /^(?:@)?thumbot wait/ }

            assert_true prw.wait_lock?
            assert_equal prw.all_comments.any? { |comment| comment[:body] =~ /^(?:@)?thumbot wait/ }, prw.wait_lock?
            assert_false PRW.wait_lock?
            client2.delete_comment(prw.repo, comment[:id])
          end
        end
      end
    end

  end
end



