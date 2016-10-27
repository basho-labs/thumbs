

unit_tests do

  test "should be able to generate base and sha specific build guid" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:build_guid)
      assert_equal "#{prw.repo.split(/\//).pop}:#{prw.pr.base.ref}:#{prw.pr.base.sha.slice(0,7)}:#{prw.pr.head.ref}:#{prw.most_recent_sha.slice(0,7)}", prw.build_guid
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
end
