#!/user/bin/env ruby

require 'rbconfig'

ruby = RbConfig::CONFIG["RUBY_INSTALL_NAME"]

tests = [
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
