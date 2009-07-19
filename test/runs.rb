#!/usr/bin/env ruby
catch :failure do
  1000.times do
    result = system "nice -n 19 test-concurrency.rb 1 1 1000"
    throw :failure unless result
  end
  puts "All runs finished ok."
end
