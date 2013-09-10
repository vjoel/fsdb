require 'rake'
require 'rake/testtask'

PRJ = "fsdb"

def version
  @version ||= begin
    require 'fsdb'
    warn "FSDB::VERSION not a string" unless FSDB::VERSION.kind_of? String
    FSDB::VERSION
  end
end

def tag
  @tag ||= "#{PRJ}-#{version}"
end

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

desc "Commit, tag, and push repo; build and push gem"
task :release => "release:is_new_version" do
  require 'tempfile'
  
  sh "gem build #{PRJ}.gemspec"

  file = Tempfile.new "template"
  begin
    file.puts "release #{version}"
    file.close
    sh "git commit --allow-empty -a -v -t #{file.path}"
  ensure
    file.close unless file.closed?
    file.unlink
  end

  sh "git tag #{tag}"
  sh "git push"
  sh "git push --tags"
  
  sh "gem push #{tag}.gem"
end

namespace :release do
  desc "Diff to latest release"
  task :diff do
    latest = `git describe --abbrev=0 --tags --match '#{PRJ}-*'`.chomp
    sh "git diff #{latest}"
  end

  desc "Log to latest release"
  task :log do
    latest = `git describe --abbrev=0 --tags --match '#{PRJ}-*'`.chomp
    sh "git log #{latest}.."
  end

  task :is_new_version do
    abort "#{tag} exists; update version!" unless `git tag -l #{tag}`.empty?
  end
end
