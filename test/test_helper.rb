ENV['RACK_ENV'] = 'test'

require 'rubygems'
require 'test/unit'
$:.unshift(File.join(File.dirname(__FILE__), '/../'))
require 'app'
require 'dust'
require 'rack/test'
require './lib/thumbs'
require 'vcr'
require 'log4r'

TESTREPO='thumbot/prtester'
TEST_PRW=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => 453)
TESTPR=453
ORGTESTREPO='basho-bin/tester'
ORGTEST_PRW=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => 27)
ORGTESTPR=27
Thumbs.start_logger if ENV.key?('DEBUG')

include Thumbs

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock # or :fakeweb
end

def cassette(name, options={}, &block)
  VCR.use_cassette(name, options,  &block)
end

#COMMENT_PAYLOAD = YAML.load(IO.read(File.join(File.expand_path(File.dirname('__FILE__'), './test/data/new_comment_payload.yml'))))

def create_test_pr(repo_name)
  # prep test data
  build_dir='/tmp/thumbs'
  FileUtils.mkdir_p(build_dir)
  test_dir="/tmp/thumbs/#{repo_name.gsub(/\//, '_').gsub(/-/, '_')}_#{DateTime.now.strftime("%s")}"
  FileUtils.rm_rf(test_dir)

  g = Git.clone("git@github.com:#{repo_name}", test_dir)
  g.checkout('master')
  pr_branch="feature_#{DateTime.now.strftime("%s")}"
  File.open("#{test_dir}/testfile1", "a") do |f|
    f.syswrite(DateTime.now.to_s)
  end

  g.add(:all => true)
  g.commit_all("creating for test PR")
  g.branch(pr_branch).checkout
  g.repack
  system("cd #{test_dir} && git push -q origin #{pr_branch}")
  client1 = Octokit::Client.new(:netrc => true)
  cassette(:create_pull_request, :record => :all) do
    pr = client1.create_pull_request(repo_name, "master", pr_branch, "Testing PR", "Thumbs Git Robot: This pr has been created for testing purposes")
    prw=Thumbs::PullRequestWorker.new(:repo => repo_name, :pr => pr.number)
    return prw
  end
end

def create_test_code_reviews(test_repo, pr_number)
  cassette(:create_test_code_review_1, :record => :all) do
    cassette(:create_test_code_review_2, :record => :all) do
    client2 = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
    client2.add_comment(test_repo, pr_number, "Great! +1", options = {})

    client3 = Octokit::Client.new(:login => ENV['GITHUB_USER2'], :password => ENV['GITHUB_PASS2'])
    client3.add_comment(test_repo, pr_number, "Looks good +1", options = {})
  end
  end
end

def remove_comments(test_repo, pr_number)
  # client2 = Octokit::Client.new(:login => ENV['ORG_MEMBER_GITHUB_USER2'], :password => ENV['ORG_MEMBER_GITHUB_PASS2'])
  # cassette(:get_pr_for_review_removal, :record => :all) do
  #   prw=Thumbs::PullRequestWorker.new(:repo => test_repo, :pr => pr_number)
  #   cassette(:remove_test_code_reviews, :record => :all) do
  #     prw.comments.each do |comment|
  #       p "removing comment #{comment.to_h[:id]}"
  #       cassette(:delete_comment, :record => :all) do
  #         p client2.delete_comment(TESTREPO, comment.to_h[:id])
  #       end
  #     end
  #   end
  # end
end

def create_org_member_test_code_reviews(test_repo, pr_number)
  cassette(:create_org_member_test_code_reviews, :record =>:all) do
    # client1 = Octokit::Client.new(:login => ENV['ORG_MEMBER_GITHUB_USER1'], :password => ENV['ORG_MEMBER_GITHUB_PASS1'])
    # client1.add_comment(test_repo, pr_number, "This is acceptable +1", options = {})
    client2 = Octokit::Client.new(:login => ENV['ORG_MEMBER_GITHUB_USER2'], :password => ENV['ORG_MEMBER_GITHUB_PASS2'])
    client2.add_comment(test_repo, pr_number, "This looks great, thank you! +1  (ok to merge)", options = {})
  end
end



