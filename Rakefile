# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs    << "test"
  t.libs    << "lib"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

RuboCop::RakeTask.new

task default: %i[test rubocop]
