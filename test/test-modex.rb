require 'fsdb/modex'

include FSDB

DEBUG_MODEX = ARGV.delete '-d'
VERBOSE_MODEX = ARGV.delete '-v'

thread_count = (ARGV.shift || 10).to_i
rep_count = (ARGV.shift || 1000).to_i

def tabbed a
  a.map {|s| s.sub(/^(\d+)/) {|n| " " * n.to_i * 20 + n}}
end

def thread_pass
  if rand < 0.1
    sleep rand/1000
  else
    Thread.pass
  end
end

modex = Modex.new
counter = 0

out = []
sharers = 0
excluders = 0
dumper = proc do |str|
  puts "*** #{str} called when there were #{sharers} threads sharing modex ***"
  puts tabbed(out[-20..-1])
  exit!
end

class TestThread < Thread
  def initialize n, outdev
    self[:id] = n
    self[:writes] = 0
    @outdev = outdev
    
    super do
      begin
        yield
      rescue => ex
        puts "#{ex}\n  #{ex.backtrace.join("\n  ")}"
        # let thread stop, but let process continue
      end
    end
  end
  
  def inspect
    "#<test thread #{self[:id]}>"
  end
  
  if DEBUG_MODEX
    def out s
      @outdev << "#{self[:id]}: #{s}"
    end
  else
    def out(*); end
  end
end

threads = (0...thread_count).map do |n|
  TestThread.new(n, out) do
    thread = Thread.current
    
    do_when_first = proc do
      sharers += 1
      if sharers > 1
        dumper["do_when_first"]
      end
    end

    do_when_last = proc do
      if sharers > 1
        dumper["do_when_last"]
      end
      sharers -= 1
    end

    rep_count.times do
      x = rand(100)
      case
      when x < 50
        thread.out "trying SH"
        modex.synchronize(Modex::SH, do_when_first, do_when_last) do
          thread.out "begin SH"
          c_old = counter
          thread_pass
          raise if excluders > 0
          raise unless counter == c_old
          thread.out "end SH"
        end
        thread_pass

      else
        thread.out "trying EX"
        modex.synchronize(Modex::EX) do
          thread.out "begin EX"
          excluders += 1
          counter += 1
          thread_pass
          raise unless excluders == 1
          raise unless sharers == 0
          excluders -= 1
          thread.out "end EX"
        end
        thread_pass
        thread[:writes] += 1
      end
    end
  end
end

expected = threads.inject(0) {|s, t| t.join; s + t[:writes]}
puts tabbed(out) if VERBOSE_MODEX

actual = counter
if expected == actual
  puts "Test passed: #{actual} write operations"
else
  puts "Test failed: #{actual} < #{expected} expected"
end
