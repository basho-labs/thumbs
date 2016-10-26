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

  test "set build progress when running build steps" do
    cassette(:load_stuff, :allow_playback_repeats => true) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      cassette(:load_stuff_other, :allow_playback_repeats => true) do
        cassette(:build_progress_steps, :allow_playback_repeats => true, :record => :all) do


          default_vcr_state do
            prw.clear_build_progress_comment

            cassette(:build_in_progress_test, :allow_playback_repeats => true, :record => :all) do
              cassette(:build_in_progress_test2, :allow_playback_repeats => true, :record => :all) do

                assert_false prw.build_in_progress?

                assert_equal :unstarted, prw.build_progress_status
                prw.build_steps=["find /tmp"]
                prw.thumb_config['timeout']=5
                prw.set_build_progress(:in_progress)
                assert_equal :in_progress, prw.build_progress_status
                prw.set_build_progress(:completed)
                assert_equal :completed, prw.build_progress_status

              end
            end

          end
        end
      end
    end
  end
end

