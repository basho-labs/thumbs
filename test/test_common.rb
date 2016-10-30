

unit_tests do

  test "should be able to generate base and sha specific build guid" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:build_guid)
      assert_equal "#{prw.pr.base.ref}:#{prw.pr.base.sha.slice(0,7)}:#{prw.pr.head.ref}:#{prw.pr.head.sha.slice(0,7)}", prw.build_guid
    end
  end


  test "can get open pull requests for repo" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      prw.respond_to?(:open_pull_requests)
      open_pull_requests = prw.client.pull_requests(prw.repo, :state => 'open')
      assert_equal open_pull_requests.collect{|pr| pr[:base][:ref] }, prw.open_pull_requests.collect{|pr| pr[:base][:ref] }
    end
  end

  test "can get open pull requests for repo and branch" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      prw.respond_to?(:pull_requests_for_base_branch)
      matched_base_pull_requests = prw.open_pull_requests.collect{|pr| pr if pr.base.ref == "master"}
      assert_equal matched_base_pull_requests.collect{|pr| pr[:base][:ref] }, prw.pull_requests_for_base_branch("master").collect{|pr| pr[:base][:ref] }
    end
  end

  test "can get commits for branch " do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      commits = prw.client.commits(TESTREPO, prw.pr.head.ref)
      assert_equal prw.commits.first[:sha], commits.first[:sha]
    end
  end

  test "can provide most recent head sha" do
    # do the most recent head sha from the branch
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      most_recent_head_sha = prw.client.commits(prw.repo, prw.pr.head.ref).first[:sha]
      assert_equal prw.pr.head.sha, most_recent_head_sha
    end
  end

  test "can provide most recent base sha" do
    # do the most recent base sha from the branch
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      most_recent_base_sha = prw.client.commits(prw.repo, prw.pr.base.ref).first[:sha]
      assert_equal prw.pr.base.sha, most_recent_base_sha
    end
  end

  # todo show scenario where pr.base.sha  and most_recent_base_sha differ.

end
