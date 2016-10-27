

unit_tests do

  test "should be able to generate base and sha specific build guid" do
    default_vcr_state do
      prw = Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.respond_to?(:build_guid)
      assert_equal "#{prw.pr.base.ref}_#{prw.most_recent_sha.slice(0,7)}", prw.build_guid
    end
  end
end
