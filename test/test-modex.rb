#!/usr/bin/env ruby

require 'fsdb/modex'

include FSDB

modex = Modex.new
counter = 0
thread_count = (ARGV.shift || 10).to_i
rep_count = (ARGV.shift || 1000).to_i

out = []
sharers = 0
excluders = 0
dumper = proc do |str|
  puts "*** #{str} called when there were #{sharers} threads sharing modex ***"
  puts out[-20..-1].join("\n")
  exit!
end

threads = (0...thread_count).map do |n|
  Thread.new do
    thread = Thread.current
    thread[:id] = n
    thread[:writes] = 0

    do_when_first = proc do
      out << "#{thread[:id]}: do_when_first"
      sharers += 1
      if sharers > 1
        dumper["do_when_first"]
      end
    end

    do_when_last = proc do
      out << "#{thread[:id]}: do_when_last"
      if sharers > 1
        dumper["do_when_last"]
      end
      sharers -= 1
    end

    rep_count.times do
      x = rand(100)
      case
      when x < 50
        out << "#{thread[:id]}: trying SH"
        modex.synchronize(Modex::SH, do_when_first, do_when_last) do
          out << "#{thread[:id]}: locked SH"
          c_old = counter
          Thread.pass
          raise if excluders > 0
          raise unless counter == c_old
          out << "#{thread[:id]}: unlocked SH"
        end
      else
        out << "#{thread[:id]}: trying EX"
        modex.synchronize(Modex::EX) do
          out << "#{thread[:id]}: locked EX"
          excluders += 1
          counter += 1
          Thread.pass
          raise unless excluders == 1
          excluders -= 1
          out << "#{thread[:id]}: unlocked EX"
        end
        thread[:writes] += 1
      end
    end
  end
end

expected = 0
threads.each {|t| t.join; expected += t[:writes]}

actual = counter

if expected == actual
  puts "Test passed: #{actual} write operations"
else
  puts "Test failed: #{actual} < #{expected} expected"
end
