require 'rake'
require 'rake/testtask'

desc "Run unit tests"
Rake::TestTask.new :test_unit do |t|
  t.libs << "lib"
  t.libs << "test/lib"
  t.test_files = FileList[
    "test/test-fsdb.rb",
    "test/test-formats.rb"
  ]
end

desc "Run stress tests"
task :test_stress do
  require 'rbconfig'
  ruby = RbConfig::CONFIG["RUBY_INSTALL_NAME"]
  tests = [
    "test/test-modex.rb",
    "test/test-concurrency.rb"
  ]

  tests.each do |test|
    cmd = [ruby, test]
    puts "running>> #{cmd.join(" ")}"
    sh *cmd
    puts "$" * 60
  end
end

desc "Run all tests"
task :test => [:test_stress, :test_unit]
