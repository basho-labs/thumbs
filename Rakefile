$:.unshift(File.dirname(__FILE__))
require 'app'
require 'thumbs'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "test"
#  t.test_files = FileList['test/test*.rb']
 # t.test_files = FileList['test/test_payload.rb','test/test_webhook.rb','test/test_persisted_build_status']
  t.test_files = FileList['test/test.rb']
  t.verbose = true
end

task :default => [:test]

task :console do
  ruby "bin/console"
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


