$:.unshift(File.dirname(__FILE__))
require 'app'
require 'thumbs'
require 'test/test_helper'
require "irb"

task :default => [:test]

task :console do
  ruby "bin/console"
end
task :test do
#  ruby FileList.new('test/*.rb')
  ruby FileList.new('test/test_minimal.rb')
end

task :start do
  ruby "./app.rb -p 4567"
end


task :create_test_pr do
  prw = create_test_pr("thumbot/prtester")
  p "PR created #{prw.repo}  # #{prw.pr.number}"
end

task :create_test_reviews do
  pr=ENV['PR']
  repo = 'thumbot/prtester'
  create_test_code_reviews(repo, pr)
end


