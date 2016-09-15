$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'

#require 'pacto'
#Pacto.generate!


unit_tests do

  test "should display build status comment" do
    # WebMock.stub_request(:post, "https://thumbot:B%2FGUk%3E~22%3Ec%2A%24I%7CIa%3C%40@api.github.com/repos/thumbot/prtester/pulls").
    #     with(:body => "{\"base\":\"master\",\"head\":\"feature_1471889677\",\"title\":\"Testing PR\",\"body\":\"Thumbs Git Robot: This pr has been created for testing purposes\"}",
    #          :headers => {'Accept'=>'application/vnd.github.v3+json', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Content-Type'=>'application/json', 'User-Agent'=>'Octokit Ruby Gem 4.3.0'}).
    #     to_return(:status => 200, :body => "", :headers => {})

    test_pr_worker=create_test_pr("davidx/prtester")
    assert test_pr_worker.validate
    test_pr_worker.create_build_status_comment

    assert test_pr_worker.comments.first['body'] =~ /Build Status/

    create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)

    assert test_pr_worker.review_count >= 2
    assert_false test_pr_worker.valid_for_merge?

    assert_true test_pr_worker.open?

    # test_pr_worker.merge

    # test_pr_worker.close

  end
  # test "should display failed build status comment" do
  #   # WebMock.stub_request(:post, "https://thumbot:B%2FGUk%3E~22%3Ec%2A%24I%7CIa%3C%40@api.github.com/repos/thumbot/prtester/pulls").
  #   #     with(:body => "{\"base\":\"master\",\"head\":\"feature_1471889677\",\"title\":\"Testing PR\",\"body\":\"Thumbs Git Robot: This pr has been created for testing purposes\"}",
  #   #          :headers => {'Accept'=>'application/vnd.github.v3+json', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Content-Type'=>'application/json', 'User-Agent'=>'Octokit Ruby Gem 4.3.0'}).
  #   #     to_return(:status => 200, :body => "", :headers => {})
  #
  #   test_pr_worker=create_unmergable_test_pr("thumbot/prtester")
  #
  #   assert test_pr_worker.validate
  #   test_pr_worker.create_build_status_comment
  #
  #   assert test_pr_worker.comments.first['body'] =~ /Build Status/
  #
  #   assert test_pr_worker.comments.first['body'] =~ /no_entry/, test_pr_worker.comments.first['body']
  #
  #   create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)
  #
  #   assert test_pr_worker.review_count >= 2
  #   assert_false test_pr_worker.valid_for_merge?
  #
  #   assert_true test_pr_worker.open?
  #
  #   test_pr_worker.merge
  #
  #   # test_pr_worker.close
  #
  # end
end
