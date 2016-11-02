unit_tests do

  test "should  respond to get_pull_request_by_id" do
    default_vcr_state do
      assert PRW.respond_to?(:get_pull_request_by_id)
    end
  end
  test "should  respond to get_reviews_by_pr_id" do
    default_vcr_state do
      assert PRW.respond_to?(:get_reviews_by_pr_id)
    end
  end

  test "should  respond to run_graph_query" do
    default_vcr_state do
      assert PRW.respond_to?(:run_graph_query)
    end
  end

  test "should  respond to approvals" do
    default_vcr_state do
      assert PRW.respond_to?(:approvals)
      assert PRW.approvals.length == 0
      cassette(:get_pull_request_id) do
        assert_equal PRW.get_approvals(PRW.pull_request_id), PRW.approvals
      end
    end
  end

  test "should  respond to get_approvals" do
    default_vcr_state do
      assert PRW.respond_to?(:get_approvals)
      assert PRW.approvals.length == 0
      code_reviews = PRW.get_reviews_by_pr_id(PRW.pull_request_id)
      approvals_by_pr_id=code_reviews.collect{|r| r if r['state'] == 'APPROVED'}.compact
      assert_equal approvals_by_pr_id, PRW.get_approvals(PRW.pull_request_id)
    end
  end

  test "should  respond to approval_count" do
    default_vcr_state do
      assert PRW.respond_to?(:approval_count)
      assert PRW.approval_count == 0
      assert_equal PRW.approvals.length, PRW.approval_count
    end
  end

  test "should respond to comment_code_approvals" do
    default_vcr_state do
      assert PRW.respond_to?(:reviews)
      assert_equal PRW.approvals + PRW.comment_code_approvals, PRW.reviews
    end
  end

  test "reviews should be a combination of comment_code_approvals and github code approvals" do
    default_vcr_state do
      assert PRW.respond_to?(:reviews)
      assert_equal PRW.approvals + PRW.comment_code_approvals, PRW.reviews
    end

  end
  test "reviews_count should be a combination of comment_code_approvals and github code approvals" do
    default_vcr_state do
      assert_equal PRW.approval_count + PRW.comment_code_approval_count, PRW.review_count
    end
  end
end
