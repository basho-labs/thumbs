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
      assert_equal "cd /tmp/thumbs/thumbot_prtester_#{prw.pr.head.sha.slice(0,8)} && uptime 2>&1", status[:command]
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
            try_merge
            run_build_steps
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
    cassette(:load_pr, :record => :new_episodes) do
      prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
      cassette(:get_comments, :record => :all) do
        comment_length = prw.comments.length
        cassette(:add_comment, :record => :all) do
          comment = prw.add_comment("test")
          cassette(:get_comments_update, :record => :all) do
            new_comment_length = prw.comments.length
            assert new_comment_length > comment_length, new_comment_length
            client1 = Octokit::Client.new(:netrc => true)

            cassette(:delete_pull_request_comment, :record => :all) do
              client1.delete_pull_request_comment(TESTREPO, comment.to_h[:id])
            end
          end
        end
      end
    end
  end


  test "uses custom build steps" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)

        prw.respond_to?(:build_steps)
        assert prw.build_steps.sort == ["make", "make test"].sort, prw.build_steps.inspect
        prw.try_merge
        prw.run_build_steps

        assert prw.build_status[:steps].keys.sort == [:merge, :make, :make_test].sort, prw.build_status[:steps]

        prw.build_steps = ["make build", "make custom"]
        prw.run_build_steps
        assert prw.build_status[:steps].keys.sort == ["merge", "make_build", "make_custom"].sort

        prw.build_steps = ["make -j2 -p -H all", "make custom"]
        prw.run_build_steps
        assert prw.build_status[:steps].keys.sort == ["merge", "make_j2_p_H", "make_custom"]
      end
    end
  end

  test "code reviews from random users are not counted" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        remove_comments(TESTREPO, TESTPR)
        assert prw.review_count == 0
        cassette(:get_state, :record => :new_episodes) do
          assert_equal false, prw.valid_for_merge?
          cassette(:create_test_code_reviews) do
            create_test_code_reviews("thumbot/prtester", prw.pr.number)
            assert prw.review_count > 2
            prw.run_build_steps
            assert_equal false, prw.valid_for_merge?, prw.build_status
          end
        end

      end
    end

  end
  test "ensure code reviews are from org members" do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        remove_comments(TESTREPO, TESTPR)

        assert prw.review_count == 0

        assert_equal false, prw.valid_for_merge?
        create_unprivileged_test_code_reviews("thumbot/prtester", prw.pr.number)
        assert prw.review_count == 0
        create_privileged_test_code_reviews("thumbot/prtester", prw.pr.number)
        assert prw.review_count == 2
        prw.try_merge
        prw.run_build_steps
        assert_equal true, prw.valid_for_merge?
      end
    end
  end

  test "should not merge if merge=false in thumbs." do
    cassette(:load_pr) do
      cassette(:load_comments) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        remove_comments(TESTREPO, TESTPR)
        prw.try_merge
        assert prw.thumb_config.key('merge')
        assert prw.thumb_config['merge'] == true

        cassette(:get_state) do
          assert_equal false, prw.valid_for_merge?
          create_privileged_test_code_reviews("thumbot/prtester", prw.pr.number)
          assert prw.review_count == 2
          assert prw.aggreg
          assert_equal false, prw.valid_for_merge?
        end
      end
    end
  end

  test "should identify org code reviews" do
    cassette(:load_pr, :record => :new_episodes) do
      cassette(:load_comments, :record => :all) do
        prw=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTPR)
        org_member_code_review_count = prw.org_member_code_reviews.length
        assert_equal false, prw.valid_for_merge?
        assert prw.respond_to?(:org_member_code_reviews)
        cassette(:create_member_reviews, :record => :all) do
          create_org_member_test_code_reviews("thumbot/prtester", prw.pr.number)
          cassette(:list_member_reviews, :record => :all) do
            assert prw.org_member_code_reviews > org_member_code_review_count
            assert prw.code_reviews == 0

            end
        end
      end
    end
  end
end
