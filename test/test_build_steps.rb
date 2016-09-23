$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'


unit_tests do

  test "can try pr merge" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      status = prw.try_merge

      assert status.key?(:result)
      assert status.key?(:message)

      assert_equal :ok, status[:result]
      assert_equal status, prw.build_status[:steps][:merge]
    end
  end
  test "can try run build step" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      status = prw.try_merge

      status = prw.try_run_build_step("uptime", "uptime")
      assert status.key?(:result)
      assert status.key?(:message)

      assert_equal :ok, status[:result]
      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert_equal "cd /tmp/thumbs/thumbot_prtester_#{prw.pr.head.sha.slice(0, 8)} && uptime 2>&1", status[:command]
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code]==0
      assert status.key?(:result)
      assert status[:result]==:ok
    end

  end
  test "can try run build step with error" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      status = prw.try_merge

      status = prw.try_run_build_step("uptime", "uptime -ewkjfdew 2>&1")

      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code]==1
      assert status.key?(:result)
      assert status[:result]==:error
    end
  end
  test "can try run build step and verify build dir" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      status = prw.try_merge
      status = prw.try_run_build_step("build", "make build")

      assert status.key?(:exit_code)
      assert status.key?(:result)
      assert status.key?(:message)
      assert status.key?(:command)
      assert status.key?(:output)

      assert status.key?(:exit_code)
      assert status[:exit_code]==0
      assert status.key?(:result)
      assert status[:result]==:ok
      build_dir_path="/tmp/thumbs/#{prw.repo.gsub(/\//, '_')}_#{prw.pr.head.sha.slice(0, 8)}"
      assert_equal "cd #{build_dir_path} && make build 2>&1", status[:command]

      assert_equal "BUILD OK\n", status[:output]
    end
  end

  test "can try run build step make test" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      status = prw.try_merge
      status = prw.try_run_build_step("make_test", "make test")

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
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert prw.minimum_reviewers==2
      assert prw.respond_to?(:reviews)
      cassette(:comments) do
        assert prw.respond_to?(:valid_for_merge?)
        cassette(:get_state) do
          assert_equal false, prw.valid_for_merge?
        end
      end
    end
  end

  test "can verify valid for merge" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        cassette(:issue_comments, :record => :new_episodes) do
          prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
          prw.build_steps=["make test"]
          cassette(:validate_comments) do
            prw.try_merge
            prw.run_build_steps
            cassette(:get_state) do
              assert_equal false, prw.valid_for_merge?
            end
          end
        end
      end
    end
  end


  test "unmergable with failing build steps" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        prw.build_steps = ["make", "make test", "make UNKNOWN_OPTION"]

        cassette(:get_open) do
          assert_equal true, prw.open?

          prw.run_build_steps
          assert_equal :error, prw.aggregate_build_status_result, prw.build_status
          step, status = prw.build_status[:steps].collect { |step_name, status| [step_name, status] if status[:result] != :ok }.compact.shift
          assert_equal step, "make_UNKNOWN_OPTION".to_sym

          assert status[:result]==:error
          assert status[:exit_code]!=0

          cassette(:get_new_comments, :record => :new_episodes) do
            assert_equal false, prw.valid_for_merge?
          end
        end
      end
    end
  end


  test "can get aggregate build status" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      assert_equal :ok, prw.aggregate_build_status_result
      prw.build_steps=["make", "make test"]
      prw.run_build_steps
      assert_equal :ok, prw.aggregate_build_status_result
      prw.build_steps=["make", "make error"]
      prw.run_build_steps

      assert_equal :error, prw.aggregate_build_status_result, prw.build_status.inspect
    end

  end
  test "add comment" do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      cassette(:get_comments) do
        comment_length = prw.comments.length
        cassette(:add_comment_test) do
          assert prw.respond_to?(:add_comment)
          comment = prw.add_comment("test")
          assert comment.to_h.key?(:created_at), comment.to_h.to_yaml
          assert comment.to_h.key?(:id), comment.to_h.to_yaml
        end
      end
    end
  end


  test "uses custom build steps" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)

        prw.respond_to?(:build_steps)
        prw.reset_build_status

        assert prw.build_steps.sort == ["make", "make test"].sort, prw.build_steps.inspect
        prw.run_build_steps
        assert prw.build_steps.sort == ["make", "make test"].sort, prw.build_steps.inspect

        assert prw.build_status[:steps].keys.sort == [:make, :make_test].sort, prw.build_status[:steps].inspect
        prw.reset_build_status

        prw.build_steps = ["make build", "make custom"]
        assert prw.build_steps.include?("make build")
        prw.run_build_steps
        assert prw.build_status[:steps].keys.sort == [:make_build, :make_custom].sort, prw.build_status[:steps].keys.sort.inspect

        prw.reset_build_status

        prw.build_steps = ["make -j2 -p -H all", "make custom"]
        prw.run_build_steps
        assert prw.build_status[:steps].keys.sort == [:make_custom, :make_j2_p_H_all].sort, prw.build_status[:steps].keys.sort.inspect
      end
    end
  end

  test "code reviews from random users are not counted" do

    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => ORGTESTREPO, :pr => ORGTESTPR)
        cassette(:load_comments_update, :record => :all) do
          cassette(:get_state, :record => :new_episodes) do
            assert_equal false, prw.valid_for_merge?

              cassette(:update_reviews, :record => :all) do
                assert prw.review_count => 2
                prw.run_build_steps
                assert_equal false, prw.valid_for_merge?, prw.build_status
              end

             end


        end
      end

    end
  end

    # test "ensure code reviews are from org members" do
    #   cassette(:load_pull_request, :record => :new_episodes) do
    #     cassette(:load_comments, :record => :new_episodes) do
    #       prw=Thumbs::PullRequestWorker.new(:repo => ORGTESTREPO, :pr => ORGTESTPR)
    #
    #       remove_comments(ORGTESTREPO, ORGTESTPR)
    #       assert prw.review_count == 0
    #       cassette(:get_state) do
    #
    #         assert_equal false, prw.valid_for_merge?
    #
    #         cassette(:issue_comments_update) do
    #
    #
    #           assert prw.review_count == 0
    #           create_org_member_test_code_reviews(ORGTESTREPO, ORGTESTPR)
    #           assert prw.review_count == 2, prw.review_count.to_s
    #           assert prw.review_count >= prw.minimum_reviewers
    #           assert prw.aggregate_build_status_result == :ok
    #
    #           prw.try_merge
    #           prw.run_build_steps
    #           cassette(:get_state_updated_false) do
    #             assert_equal false, prw.valid_for_merge?
    #             cassette(:get_state_updated_true) do
    #               prw.thumb_config['merge']=true
    #               assert_equal true, prw.valid_for_merge?
    #             end
    #           end
    #         end
    #       end
    #     end
    #   end
    # end


  test "should not merge if merge false in thumbs." do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        #remove_comments(TESTREPO, TESTPR)
        prw.try_merge
        assert prw.thumb_config.key?('merge')
        assert prw.thumb_config['merge'] == false

        cassette(:get_state) do
          assert_equal false, prw.valid_for_merge?
          create_test_code_reviews(TESTREPO, TESTPR)
          cassette(:get_post_code_review_count) do
            assert prw.review_count >= 2, prw.review_count.to_s
            assert prw.aggregate_build_status_result == :ok
            cassette(:get_updated_state) do
              assert_equal false, prw.valid_for_merge?
            end
          end
        end
      end
    end
  end

  test "should identify org code reviews" do
    cassette(:remove_org_comments, :record => :all) do
      remove_comments(ORGTESTREPO, ORGTESTPR)

      cassette(:load_org_pr) do
        cassette(:load_org_comments_issues) do
          prw=Thumbs::PullRequestWorker.new(:repo => ORGTESTREPO, :pr => ORGTESTPR)
          cassette(:get_comments_issues, :record => :all) do
            org_member_code_review_count = prw.org_member_code_reviews.length
            assert_equal false, prw.valid_for_merge?
            assert prw.respond_to?(:org_member_code_reviews), "doesnt respond to"
            create_org_member_test_code_reviews(ORGTESTREPO, ORGTESTPR)
            cassette(:post_add_code_review_update, :record => :all) do

              assert prw.org_member_code_reviews.length > org_member_code_review_count, org_member_code_review_count.to_s
              remove_comments(ORGTESTREPO, ORGTESTPR)
            end
          end
        end
      end

    end
  end
end
