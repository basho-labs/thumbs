unit_tests do

  test "can NOT merge forked branch repo" do
     default_vcr_state do
        prw=Thumbs::PullRequestWorker.new(:repo => 'davidx/prtester', :pr => 323)

        status = prw.try_merge

        assert status.key?(:result)
        assert status.key?(:message)

        assert_equal :error, status[:result]
        assert_equal status, prw.build_status[:steps][:merge]
     end
  end
end



