$:.unshift(File.dirname(__FILE__))
require 'app'
require 'thumbs'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test.rb']
  t.verbose = true
end
task :default => [:test]

task :console do
  ruby "bin/console"
end

