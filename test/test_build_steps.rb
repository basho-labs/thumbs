unit_tests do

  test "can try pr merge" do
    default_vcr_state do
      status = PRW.try_merge

      assert status.key?(:result)
      assert status.key?(:message)

      assert_equal :ok, status[:result]
      assert_equal status, PRW.build_status[:main][:steps][:merge]
    end
  end
  test "can try run build step" do
    default_vcr_state do
      status = PRW.try_merge

      status = PRW.try_run_build_step("uptime", "uptime")
      assert status.key?(:result)
      assert status.key?(:message)

      assert_equal :ok, status[:result]
      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      build_dir_path="/tmp/thumbs/#{PRW.build_guid}"
      assert_equal "cd #{build_dir_path}; uptime", status[:command]
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code]==0
      assert status.key?(:result)
      assert status[:result]==:ok
    end

  end
  test "can try run build step with error" do
    default_vcr_state do
      status = PRW.try_merge
      status = PRW.try_run_build_step("uptime", "uptime -ewkjfdew")

      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code] != 0, status[:exit_code].inspect
      assert status.key?(:result)
      assert status[:result]==:error
    end
  end
  test "can try run build step and verify build dir" do
    default_vcr_state do
      status = PRW.try_merge
      status = PRW.try_run_build_step("build", "make build")

      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code]==0
      assert status.key?(:result)
      assert status[:result]==:ok
      build_dir_path="/tmp/thumbs/#{PRW.build_guid}"

      assert_equal "cd #{build_dir_path}; make build", status[:command]

      assert_equal "BUILD OK\n", status[:output]
    end
  end

  test "can try run build step make test" do
    default_vcr_state do
      status = PRW.try_merge

      status = PRW.try_run_build_step("make_test", "make test")

      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert status.key?(:output)

      assert_equal "TEST OK\n", status[:output]
      assert status.key?(:exit_code)
      assert status[:exit_code]==0
      assert status.key?(:result)
      assert status[:result]==:ok
    end
  end


  test "pr should not be merged" do
    default_vcr_state do
      assert PRW.minimum_reviewers==2
      assert PRW.respond_to?(:reviews)
      cassette(:comments) do
        assert PRW.respond_to?(:valid_for_merge?)
        cassette(:get_state) do
          cassette(:get_commits) do
            assert_equal false, PRW.valid_for_merge?
          end
        end
      end
    end
  end

  test "can verify valid for merge" do
    default_vcr_state do
      PRW.build_steps=["make test"]
      PRW.try_merge
      PRW.run_build_steps
      cassette(:get_state) do
        cassette(:get_commits) do
          cassette(:get_more_commits) do
            assert_equal false, PRW.valid_for_merge?
          end
        end
      end
    end
  end

  test "unmergable with failing build steps" do
    default_vcr_state do
      cassette(:get_events_unmergable) do

        UNMERGABLEPRW.build_steps = ["make", "make test", "make UNKNOWN_OPTION"]
        cassette(:get_state, :record => :new_episodes) do

          cassette(:get_open) do
            assert_equal true, UNMERGABLEPRW.open?
            UNMERGABLEPRW.reset_build_status
            UNMERGABLEPRW.unpersist_build_status
            UNMERGABLEPRW.try_merge
            cassette(:commits, :record => :new_episodes) do
              cassette(:commits_update, :record => :new_episodes) do

                UNMERGABLEPRW.run_build_steps
                assert_equal :error, UNMERGABLEPRW.aggregate_build_status_result, UNMERGABLEPRW.build_status
                step, status = UNMERGABLEPRW.build_status[:main][:steps].collect { |step_name, status| [step_name, status] if status[:result] != :ok }.compact.shift
                assert_equal :merge, step

                assert status[:result]==:error
                assert status[:exit_code]!=0

                cassette(:get_new_comments, :record => :new_episodes) do
                  assert_equal false, UNMERGABLEPRW.valid_for_merge?
                end
              end

            end
          end
        end

      end
    end
  end


  test "can get aggregate build status" do
    default_vcr_state do
      PRW.unpersist_build_status
      PRW.reset_build_status
      PRW.build_steps=["make", "make test"]
      PRW.run_build_steps
      assert_equal :ok, PRW.aggregate_build_status_result
      PRW.unpersist_build_status
      PRW.reset_build_status
      PRW.clear_build_progress_comment
      PRW.build_steps=["make", "make error"]
      PRW.run_build_steps
      cassette(:new_agg_result, :record => :new_episodes) do
        assert_equal :error, PRW.aggregate_build_status_result, PRW.build_status.inspect
      end
    end
  end
  test "add comment" do
    default_vcr_state do
      comment_length = PRW.comments.length
      cassette(:add_comment_test) do
        assert PRW.respond_to?(:add_comment)
        comment = PRW.add_comment("test")
        assert comment.to_h.key?(:created_at), comment.to_h.to_yaml
        assert comment.to_h.key?(:id), comment.to_h.to_yaml
      end
    end
  end


  test "uses custom build steps" do
    default_vcr_state do
      PRW.respond_to?(:build_steps)
      PRW.reset_build_status
      PRW.unpersist_build_status
      assert PRW.build_status[:main][:steps] == {}, PRW.build_status[:main][:steps].inspect
      PRW.build_steps = ["make", "make test"]
      PRW.run_build_steps
      assert PRW.build_steps.sort == ["make", "make test"].sort, PRW.build_steps.inspect

      assert PRW.build_status[:main][:steps].keys.sort == [:make, :make_test].sort, PRW.build_status[:main][:steps].inspect
      PRW.reset_build_status
      PRW.unpersist_build_status

      PRW.build_steps = ["make build", "make custom"]

      assert PRW.build_steps.include?("make build")
      PRW.run_build_steps

      assert PRW.build_status[:main][:steps].keys.include?(:make_build), PRW.build_status[:main][:steps].keys.inspect

      PRW.reset_build_status

      PRW.build_steps = ["make -j2 -p -H all", "make custom"]
      PRW.run_build_steps
      assert PRW.build_status[:main][:steps].keys.sort == [:make_custom, :make_j2_p_H_all].sort, PRW.build_status[:main][:steps].keys.sort.inspect

    end
  end

  test "code reviews from random users are not counted" do
    default_vcr_state do
      cassette(:load_comments_update, :record => :all) do
        cassette(:get_state, :record => :new_episodes) do
          assert_equal false, ORGPRW.valid_for_merge?
          cassette(:update_reviews, :record => :all) do
            assert ORGPRW.review_count => 2
            ORGPRW.run_build_steps
            assert_equal false, ORGPRW.valid_for_merge?, ORGPRW.build_status
          end
        end
      end
    end
  end
  test "should not merge if merge false in thumbs." do
    default_vcr_state do
      PRW.reset_build_status
      PRW.unpersist_build_status
      PRW.try_merge
      assert PRW.thumb_config.key?('merge')
      assert PRW.thumb_config['merge'] == false
      cassette(:get_state, :record => :all) do
        assert_equal false, PRW.valid_for_merge?
        cassette(:create_code_reviews, :record => :all) do
          create_test_code_reviews(TESTREPO, TESTPR)
          assert PRW.review_count >= 1, PRW.review_count.to_s
          cassette(:get_post_code_review_count, :record => :all) do
            assert PRW.aggregate_build_status_result == :ok
            cassette(:get_updated_state, :record => :all) do
              assert_equal false, PRW.valid_for_merge?
              cassette(:get_valid_for_merge, :record => :all) do
                PRW.validate
                PRW.thumb_config['merge'] = true
                PRW.thumb_config['minimum_reviewers'] = 0
                assert_equal true, PRW.valid_for_merge?
              end
            end
          end
        end
      end
    end
  end

  test "should not merge if wait_lock?" do
    cassette(:get_wait_lock_pr, :record => :new_episodes) do
      prw = Thumbs::PullRequestWorker.new(repo: 'davidx/prtester', pr: 323)
      prw.validate
      prw.thumb_config['merge'] = true
      prw.thumb_config['minimum_reviewers'] = 0
      client2 = Octokit::Client.new(:netrc => true,
                                    :netrc_file => ".netrc.davidpuddy1")
      cassette(:get_updated_comments, :record => :new_episodes) do
        cassette(:get_valid_for_merge_update, :record => :all) do
          cassette(:get_valid_for_merge_update_refresh, :record => :all) do
            assert_equal true, prw.wait_lock?
            assert_equal false, prw.valid_for_merge?
          end
        end
      end
    end
  end

  test "should identify org comments" do
    default_vcr_state do
      assert ORGPRW.respond_to?(:org_member_comments)
      org=ORGPRW.repo.split(/\//).shift
      org_member_comments = ORGPRW.non_author_comments.collect { |comment| comment if ORGPRW.client.organization_member?(org, comment[:user][:login]) }.compact
      assert_equal ORGPRW.org_member_comments, org_member_comments
    end
  end

  test "should identify org code reviews" do
    default_vcr_state do
      assert ORGPRW.respond_to?(:org_member_code_reviews)
      org=ORGPRW.repo.split(/\//).shift
      org_member_comments = ORGPRW.non_author_comments.collect { |comment| comment if ORGPRW.client.organization_member?(org, comment[:user][:login]) }.compact
      org_member_code_reviews=org_member_comments.collect { |comment| comment if ORGPRW.contains_plus_one?(comment[:body]) }.compact
      assert_equal ORGPRW.org_member_code_reviews, org_member_code_reviews
    end
  end

  test "can get events for pr" do
    default_vcr_state do
      assert PRW.respond_to?(:events)
      events = PRW.events
      assert events.kind_of?(Array)
      assert events.first.kind_of?(Hash)
      assert events.first.key?(:created_at)
    end
  end

  test "can get comments after sha" do
    default_vcr_state do
      comments = PRW.comments
      sha_time_stamp=PRW.push_time_stamp(PRW.pr.head.sha)
      comments_after_sha=PRW.client.issue_comments(PRW.repo, PRW.pr.number, per_page: 100).collect { |c| c.to_h if c[:created_at] > sha_time_stamp }.compact
      assert_equal comments_after_sha, comments
    end
  end

  test "can get interpreter build_steps" do
    default_vcr_state do
      PRW.respond_to?(:interpreter_build_steps)
      build_steps = PRW.interpreter_build_steps
      interpreter=build_steps.keys.first
      path = build_steps[interpreter]
    end
  end
  test "can get alternate build_steps" do
    default_vcr_state do
    end
  end

  def interpreter_build_steps
    thumb_config.select { |k, v| k['build_steps_'] }
  end

  def run_interpreter_build_steps
    debug_message "running interpreter specific build_steps"
    # => {"build_steps_18"=>["env", "uptime"], "build_steps_R16B03"=>["env", "uptime"]}
    interpreter_build_steps.each do |build_step|
      configured_otp_version = build_step.gsub(/build_steps_/, '')
      debug_message "got otp version #{configured_otp_version}"
      if otp_installations.include?(configured_otp_version)

      else

      end

      #      => {"R16B03"=>"/usr/local/erlang"}
      otp_installations.each do |installed_otp_version, path|
        if configured_otp_version == installed_otp_version

        end
# make generic, so can be used for any version of any lang.
# #initially only support kerl, then add rvm. it'll check to see if that version script exists and load it."
# build_steps_2.3: :build_steps_ruby-3.4":
      end
    end

  end
end


