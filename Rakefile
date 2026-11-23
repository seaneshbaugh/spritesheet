# frozen_string_literal: true

require 'rake/testtask'

task :assets do
  sh 'bin/css build'
end

Rake::TestTask.new do |task|
  task.libs << 'test'
  task.pattern = 'test/*_test.rb'
end

Rake::TestTask.new('test:system') do |task|
  task.libs << 'test'
  task.pattern = 'test/system/*_test.rb'
end

task test: :assets
task 'test:system' => :assets
desc 'Run regular and system tests'
task 'test:all' => ['test', 'test:system']
task default: :test
