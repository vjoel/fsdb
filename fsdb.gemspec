# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "fsdb"
  s.version = "0.7.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Joel VanderWerf"]
  s.date = "2011-12-06"
  s.description = "A file system data base. Provides a thread-safe, process-safe Database class.\nEach entry is a separate file referenced by its relative path. Allows multiple\nfile formats and serialization methods. Pure ruby and very light weight.\n"
  s.email = "vjoel@users.sourceforge.net"

  s.extra_rdoc_files = %w{ History.txt README.markdown }
  s.files =
    %w{ History.txt README.markdown } +
    Dir.glob("{bench,examples,lib,test}/**/*")

  s.homepage = "http://rubyforge.org/projects/fsdb/"
  s.rdoc_options = ["--main", "README.markdown"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "fsdb"
  s.rubygems_version = "1.8.11"
  s.summary = "File System Database"

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
