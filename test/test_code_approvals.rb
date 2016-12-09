unit_tests do
  test "should  respond to run_graph_query" do
    default_vcr_state do
      assert PRW.respond_to?(:run_graph_query)
    end
  end

  test "should  respond to approvals" do
    default_vcr_state do
      assert PRW.respond_to?(:approvals)
      assert PRW.approvals.length == 0
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
