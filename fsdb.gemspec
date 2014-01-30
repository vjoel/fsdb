require 'fsdb'

Gem::Specification.new do |s|
  s.name = "fsdb"
  s.version = FSDB::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["Joel VanderWerf"]
  s.date = Time.now.strftime "%Y-%m-%d"
  s.description = "A file system data base. Provides a thread-safe, process-safe Database class. Each entry is a separate file referenced by its relative path. Allows multiple file formats and serialization methods. Pure ruby and very light weight."
  s.email = "vjoel@users.sourceforge.net"
  s.extra_rdoc_files = ["History.txt", "README.md"]
  s.files = Dir[
    "History.txt", "README.md", "Rakefile",
    "{bench,examples,lib,test}/**/*"
  ]
  s.test_files = Dir["test/*.rb"]
  s.homepage = "https://github.com/vjoel/fsdb"
  s.rdoc_options = [
    "--quiet", "--line-numbers", "--inline-source",
    "--title", "FSDB", "--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "fsdb"
  s.summary = "File System Database"
end
