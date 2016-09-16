$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'

@prw =create_test_pr("davidx/prtester")

unit_tests do

  test "should be able to read build status" do
    # can get build status from build status persistence


    status = read_build_status(@prw.repo, @pr.head.sha)

    assert nil, status

    assert nil, @prw.build_status
    prw.run_build_steps

    status = get_persisted_build_status(repo, rev)
    assert status.kind_of?(Hash)

  end

  test "should generate build status" do


    assert_nil test_pr_worker.build_status
    assert test_pr_worker.validate

    assert test_pr_worker.build_status.key?(:steps)

    if File.exist?("#{repo}_#{rev}/build_status.yml")

    end

  end



end
