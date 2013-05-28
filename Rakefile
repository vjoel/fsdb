require 'rake'
require 'rake/testtask'

def cur_ruby
  require 'rbconfig'
  @cur_ruby ||= RbConfig::CONFIG["RUBY_INSTALL_NAME"]
end

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
  tests = [
    "test/test-modex.rb",
    "test/test-concurrency.rb"
  ]

  tests.each do |test|
    cmd = [cur_ruby, test]
    puts "running>> #{cmd.join(" ")}"
    sh *cmd
    puts "$" * 60
  end
end

desc "Run all tests"
task :test => [:test_stress, :test_unit]

desc "Run unit benchmarks"
task :bench_unit do
  sh "bench/bench.rb"
end

desc "Run system benchmarks"
task :bench_system do
  sh cur_ruby, "test/test-concurrency.rb", "-b"
end

