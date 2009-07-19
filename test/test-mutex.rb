#!/usr/bin/env ruby

require 'fsdb/mutex'

include FSDB

mutex = Mutex.new
counter = 0
thread_count = (ARGV.shift || 10).to_i
rep_count = (ARGV.shift || 1000).to_i

threads = (0...thread_count).map do |n|
  Thread.new do
    thread = Thread.current
    thread[:id] = n
    rep_count.times do
      mutex.synchronize do
        counter += 1
      end
    end
  end
end

threads.each {|t| t.join}

expected = thread_count * rep_count
actual = counter

if expected == actual
  puts "Test passed: #{actual} operations"
else
  puts "Test failed: #{actual} < #{expected} expected"
end
