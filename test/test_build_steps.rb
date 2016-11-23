unit_tests do

  test "can try pr merge" do
    default_vcr_state do
      status = PRW.try_merge

      assert status.key?(:result)
      assert status.key?(:message)

      assert_equal :ok, status[:result]
      assert_equal status, PRW.build_status[:steps][:merge]
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

        cassette(:get_open) do
          assert_equal true, UNMERGABLEPRW.open?
          UNMERGABLEPRW.reset_build_status
          UNMERGABLEPRW.unpersist_build_status
          UNMERGABLEPRW.try_merge
          UNMERGABLEPRW.run_build_steps
          assert_equal :error, UNMERGABLEPRW.aggregate_build_status_result, UNMERGABLEPRW.build_status
          step, status = UNMERGABLEPRW.build_status[:steps].collect { |step_name, status| [step_name, status] if status[:result] != :ok }.compact.shift
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


  test "can get aggregate build status" do
    default_vcr_state do
      assert_equal :ok, PRW.aggregate_build_status_result
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
      assert PRW.build_status[:steps] == {}, PRW.build_status[:steps].inspect
      PRW.build_steps = ["make", "make test"]
      PRW.run_build_steps
      assert PRW.build_steps.sort == ["make", "make test"].sort, PRW.build_steps.inspect

      assert PRW.build_status[:steps].keys.sort == [:make, :make_test].sort, PRW.build_status[:steps].inspect
      PRW.reset_build_status

      PRW.build_steps = ["make build", "make custom"]
      assert PRW.build_steps.include?("make build")
      PRW.run_build_steps

      assert PRW.build_status[:steps].keys.sort == [:make_build, :make_custom].sort, PRW.build_status[:steps].keys.sort.inspect

      PRW.reset_build_status

      PRW.build_steps = ["make -j2 -p -H all", "make custom"]
      PRW.run_build_steps
      assert PRW.build_status[:steps].keys.sort == [:make_custom, :make_j2_p_H_all].sort, PRW.build_status[:steps].keys.sort.inspect

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
end


