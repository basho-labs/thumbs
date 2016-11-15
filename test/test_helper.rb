require 'rubygems'
require 'bundler/setup'
$:.unshift(File.join(File.dirname(__FILE__), '/../vendor'))
require 'docker/docker'

require 'test/unit'
require 'app'
require 'dust'
require 'rack/test'
require './lib/thumbs'
require 'vcr'
require 'log4r'

TESTBRANCH='feature_1474522484'
TESTREPO='thumbot/prtester'
PRW=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => 453)
TESTPR=453
ORGTESTREPO='basho-bin/tester'
ORGPRW=Thumbs::PullRequestWorker.new(:repo => ORGTESTREPO, :pr => 27)
ORGTESTPR=27
TESTUNMERGABLEPR=452
UNMERGABLEPRW=Thumbs::PullRequestWorker.new(:repo => TESTREPO, :pr => TESTUNMERGABLEPR)
Thumbs.start_logger if ENV.key?('DEBUG')

def debug_message(message)
  ENV.key?('DEBUG') ? Log4r::Logger['Thumbs'].debug(message) : nil
end
include Thumbs

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock # or :fakeweb
  #config.debug_logger = File.open(File.join(File.dirname(__FILE__), 'vcr.debug.log'), 'w')
end

def cassette(name, options={}, &block)
  VCR.use_cassette(name, options, &block)
end
def default_vcr_state(&block)
  cassette(:load_pull_request, :allow_playback_repeats => true) do
    cassette(:load_comments, :record => :new_episodes, :allow_playback_repeats => true) do
      cassette(:get_comments_issues, :record => :new_episodes, :allow_playback_repeats => true) do
        cassette(:get_events_other, :allow_playback_repeats => true) do
          cassette(:get_events, :allow_playback_repeats => true, :record => :new_episodes) do
            cassette(:get_pull_events, :record => :all, :allow_playback_repeats => true) do
            cassette(:get_even_more_commits, :record => :new_episodes, :allow_playback_repeats => true) do
              block.call
		end
            end
          end
        end
      end
    end
  end
end
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
      client2 = Octokit::Client.new( :netrc => true,
                                     :netrc_file => ".netrc.davidpuddy1" )
      client2.add_comment(test_repo, pr_number, "Great! +1", options = {})
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
  cassette(:create_org_member_test_code_reviews, :record => :all) do
    client1 = Octokit::Client.new( :netrc => true,
                                   :netrc_file => ".netrc.davidpuddy1" )
    client1.add_comment(test_repo, pr_number, "This looks great, thank you! +1  (ok to merge)", options = {})
  end
end

module Octokit
  module Authentication
    def netrc_exist?(file)
      (file ? File.exist?(file) : false)
    end
    def netrc_by_file_name(netrc_file_name)
      file_path=File.join("#{ENV['HOME']}", "#{netrc_file_name}")
      File.exist?(file_path) && File.file?(file_path) && netrc_exist?(file_path) ? file_path : nil
    end
    def login_from_netrc(custom_netrc_file=nil)
      return unless netrc? || netrc_exist?(custom_netrc_file)
      begin
        require 'netrc'
        info = (custom_netrc_file ? Netrc.read(custom_netrc_file) : Netrc.read(netrc_file))
        netrc_host = URI.parse(api_endpoint).host
        creds = info[netrc_host]
        if creds.nil?
          # creds will be nil if there is no netrc for this end point
          octokit_warn "Error loading credentials from netrc file for #{api_endpoint}"
        else
          creds = creds.to_a
          self.login = creds.shift
          self.password = creds.shift
        end
      rescue LoadError
        octokit_warn "Please install netrc gem for .netrc support"
      end

    end
  end


  class Client
    def initialize(options = {})
      netrc_file=options[:netrc_file]
      Octokit::Configurable.keys.each do |key|
        instance_variable_set(:"@#{key}", options[key] || Octokit.instance_variable_get(:"@#{key}"))
      end
      file_name=netrc_by_file_name(options[:netrc_file])
      login_from_netrc(file_name) unless user_authenticated? || application_authenticated?
    end
  end
end


module Test
  module Unit
    def assert_nothing_raised(*)
      yield
    end
  end
end




