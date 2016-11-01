unit_tests do

  test "should  respond to get_pull_request_by_id" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:get_pull_request_by_id)

    end
  end
  test "should  respond to get_reviews_by_pr_id" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:get_reviews_by_pr_id)
    end
  end

  test "should  respond to run_graph_query" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:run_graph_query)
    end
  end

  test "should  respond to approvals" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:approvals)
      assert prw.approvals.length == 0
      assert_equal prw.get_approvals(prw.get_pull_request_id), prw.approvals

    end
  end

  test "should  respond to get_approvals" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:get_approvals)
      assert prw.approvals.length == 0
      code_reviews = prw.get_reviews_by_pr_id(prw.get_pull_request_id)
      approvals_by_pr_id=code_reviews.collect{|r| r if r['state'] == 'APPROVED'}.compact
      assert_equal approvals_by_pr_id, prw.get_approvals(prw.get_pull_request_id)
    end
  end

  test "should  respond to approval_count" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:approval_count)
      assert prw.approval_count == 0
      assert_equal prw.approvals.length, prw.approval_count
    end
  end

  test "should respond to comment_code_approvals" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:reviews)
      assert_equal prw.approvals + prw.comment_code_approvals, prw.reviews
    end
  end

  test "reviews should be a combination of comment_code_approvals and github code approvals" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:reviews)
      assert_equal prw.approvals + prw.comment_code_approvals, prw.reviews
    end

  end
  test "reviews_count should be a combination of comment_code_approvals and github code approvals" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert_equal prw.approval_count + prw.comment_code_approval_count, prw.review_count
    end

  end

end
