#!/user/bin/env ruby

require 'rbconfig'

ruby = Config::CONFIG["RUBY_INSTALL_NAME"]

tests = [
  "test-mutex.rb",
  "test-modex.rb",
  "test-fsdb.rb",
  "test-formats.rb",
  "test-concurrency.rb"
]

tests.each do |test|
  cmd = "#{ruby} #{test}"
  puts "running>> #{cmd}"
  system cmd
end
