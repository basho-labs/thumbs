$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'


unit_tests do

  test "can try pr merge" do
    test_pr_worker=create_test_pr("thumbot/prtester")
    create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)
    assert test_pr_worker.respond_to?(:try_merge)
    status = test_pr_worker.try_merge

    assert status.key?(:result)
    assert status.key?(:message)

    assert_equal :ok, status[:result]

    status = test_pr_worker.try_run_build_step("uptime", "uptime")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==0
    assert status.key?(:result)
    assert status[:result]==:ok

    status = test_pr_worker.try_run_build_step("uptime", "uptime -ewkjfdew 2>&1")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==1
    assert status.key?(:result)
    assert status[:result]==:error

    status = test_pr_worker.try_run_build_step("build", "make build")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==0
    assert status.key?(:result)
    assert status[:result]==:ok

    assert_equal "cd /tmp/thumbs/#{test_pr_worker.repo.gsub(/\//, '_')}_#{test_pr_worker.pr.number} && make build 2>&1", status[:command]
    assert_equal "BUILD OK\n", status[:output]

    status = test_pr_worker.try_run_build_step("test", "make test")

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
    test_pr_worker.close
  end
  test "should pr not be merged" do
    test_pr_worker=create_test_pr("thumbot/prtester")

    pr = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)
    assert test_pr_worker.respond_to?(:reviews)

    assert test_pr_worker.review_count == 0

    assert test_pr_worker.respond_to?(:valid_for_merge?)
    assert_false test_pr_worker.valid_for_merge?
    test_pr_worker.close
  end

  test "merge pr" do
    test_pr_worker=create_test_pr("thumbot/prtester")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)
    assert pr_worker.review_count == 0

    assert_false pr_worker.valid_for_merge?
    create_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)

    assert pr_worker.review_count == 2

    pr_worker.validate

    assert_true pr_worker.valid_for_merge?, pr_worker.build_status

    pr_worker.merge

    prw2 = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)

    assert prw2.kind_of?(Thumbs::PullRequestWorker), prw2.inspect

    assert_equal "thumbot/prtester", prw2.repo
    assert_false prw2.valid_for_merge?
    assert_false prw2.open?

  end
  test "webhook_unmergeable_pr_test" do
    test_pr_worker = create_test_pr("thumbot/prtester")
    test_pr_worker.build_steps = ["make", "make test", "make UNKNOWN_OPTION"]
    new_pr_webhook_payload = {
        'repository' => {'full_name' => test_pr_worker.repo},
        'number' => test_pr_worker.pr.number,
        'pull_request' => {'number' => test_pr_worker.pr.number, 'body' => test_pr_worker.pr.body}
    }

    assert_true test_pr_worker.open?
    assert test_pr_worker.validate
    test_pr_worker.create_build_status_comment

    assert test_pr_worker.comments.first['body'] =~ /Build Status/

    assert test_pr_worker.comments.first['body'] =~ /no_entry/, test_pr_worker.comments.first['body']

    create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)

    assert test_pr_worker.review_count >= 2
    assert_false test_pr_worker.valid_for_merge?

    assert_true test_pr_worker.open?
    test_pr_worker.close
  end

  test "add comment" do
    client1 = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])

    test_pr_worker = create_test_pr("thumbot/prtester")
    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)
    comments_list = pr_worker.comments

    client1.add_comment(test_pr_worker.repo, test_pr_worker.pr.number, "Adding", options = {})

    pr_worker.add_comment("comment")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)

    new_comments_list = pr_worker.comments
    assert new_comments_list.length > comments_list.length
    pr_worker.close
    assert pr_worker.state == "closed"
  end

  test "uses custom build steps" do
    test_pr_worker = create_test_pr("thumbot/prtester")

    test_pr_worker.respond_to?(:build_steps)
    assert test_pr_worker.build_steps == ["make", "make build", "make test"], test_pr_worker.build_steps.to_s
    test_pr_worker.validate

    test_pr_worker.build_status.keys.sort == ["merge", "make_build", "make_test"]

    test_pr_worker.build_steps = ["make build", "make custom"]
    test_pr_worker.validate
    test_pr_worker.build_status.keys.sort == ["merge", "make_build", "make_custom"]

    test_pr_worker.build_steps = ["make -j2 -p -H all", "make custom"]
    test_pr_worker.validate
    test_pr_worker.build_status.keys.sort == ["merge", "make_j2_p_H", "make_custom"]

    test_pr_worker.close

  end
  test "code reviews from random users are not counted" do
    test_pr_worker=create_test_pr("thumbot/prtester")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)

    assert pr_worker.review_count == 0
    assert_false pr_worker.valid_for_merge?

    create_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)

    assert pr_worker.review_count == 2

    pr_worker.validate

    assert_false pr_worker.valid_for_merge?, pr_worker.build_status

    test_pr_worker.close
  end
  test "ensure code reviews are from org members" do
    test_pr_worker=create_test_pr("thumbot/prtester")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)
    assert pr_worker.review_count == 0

    assert_false pr_worker.valid_for_merge?
    create_unprivileged_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)

    assert pr_worker.review_count == 0

    create_privileged_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)

    assert pr_worker.review_count == 2
    pr_worker.validate

    assert_true pr_worker.valid_for_merge?

    test_pr_worker.close

  end

  test "should not merge if merge=false in thumbs." do
    test_pr_worker=create_test_pr("thumbot/prtester")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)

    assert_false pr_worker.valid_for_merge?
    create_privileged_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)
    assert pr_worker.review_count == 2


    test_pr_worker.close
  end

  test "should know org code reviews" do
    test_pr_worker=create_test_pr("thumbot/prtester")
    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr_worker.repo, :pr => test_pr_worker.pr.number)

    assert_false pr_worker.valid_for_merge?


    assert pr_worker.respond_to?(:org_member_code_reviews)


    create_privileged_test_code_reviews("thumbot/prtester", test_pr_worker.pr.number)
    assert pr_worker.review_count == 2


    test_pr_worker.close
  end
end
