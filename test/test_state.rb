unit_tests do
  test "can read build progress status" do
    default_vcr_state do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      cassette(:clear_build_comment, :allow_playback_repeats => true, :record => :all) do
        prw.clear_build_progress_comment

        assert_equal :unstarted, prw.build_progress_status

      end

    end
  end


  test "can get pushes" do
    default_vcr_state do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      pushes = prw.events.collect { |e| e if e[:type] == 'PushEvent' }.compact
      assert_equal pushes, prw.pushes
    end
  end

  test "can get most_recent_sha" do
    default_vcr_state do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)

      assert_equal prw.pr.head.sha, prw.most_recent_sha
    end

  end

end
