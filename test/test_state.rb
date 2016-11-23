unit_tests do
  test "can read build progress status" do
    default_vcr_state do
      cassette(:clear_build_comment, :allow_playback_repeats => true, :record => :all) do
        prw=Thumbs::PullRequestWorker.new(repo: 'thumbot/prtester', pr: 446)
        assert_equal :unstarted, prw.build_progress_status
      end
    end
  end

  test "can get pushes" do
    default_vcr_state do
      pushes = PRW.events.collect { |e| e if e[:type] == 'PushEvent' }.compact
      assert_equal pushes, PRW.pushes
    end
  end

  test "can get most_recent_sha" do
    default_vcr_state do
      assert_equal PRW.pr.head.sha, PRW.most_recent_sha
    end
  end
end
