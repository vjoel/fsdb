require 'rake'
require 'rake/testtask'

desc "Run tests"
Rake::TestTask.new :test do |t|
  t.libs << "lib"
  t.libs << "test/lib"
  t.test_files = FileList[
    "test/test-modex.rb",
    "test/test-fsdb.rb",
    "test/test-formats.rb",
    "test/test-concurrency.rb"
  ]
end
