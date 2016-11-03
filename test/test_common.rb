

unit_tests do

  test "should be able to generate base and sha specific build guid" do
    default_vcr_state do
      assert PRW.respond_to?(:build_guid)
      assert_equal "#{PRW.pr.base.ref.gsub(/\//, '_')}##{PRW.pr.base.sha.slice(0,7)}##{PRW.pr.head.ref.gsub(/\//, '_')}##{PRW.pr.head.sha.slice(0,7)}", PRW.build_guid
    end
  end


  test "can get open pull requests for repo" do
    default_vcr_state do
      PRW.respond_to?(:open_pull_requests)
      open_pull_requests = PRW.client.pull_requests(PRW.repo, :state => 'open')
      assert_equal open_pull_requests.collect{|pr| pr[:base][:ref] }, PRW.open_pull_requests.collect{|pr| pr[:base][:ref] }
    end
  end

  test "can get open pull requests for repo and branch" do
    default_vcr_state do
      PRW.respond_to?(:pull_requests_for_base_branch)
      matched_base_pull_requests = PRW.open_pull_requests.collect{|pr| pr if pr.base.ref == "master"}
      assert_equal matched_base_pull_requests.collect{|pr| pr[:base][:ref] }, PRW.pull_requests_for_base_branch("master").collect{|pr| pr[:base][:ref] }
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

end


