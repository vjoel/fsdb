#!/usr/bin/env ruby

### only use this if you can ensure Thread.critical is not already set!

# Make sure we use the fast definition, not the thread.rb one!
class Thread # :nodoc:
  def self.exclusive
    old = critical
    self.critical = true
    yield
  ensure
    self.critical = old
  end
end

class Thread
  def self.nonexclusive
    old = critical
    self.critical = false
    yield
  ensure
    self.critical = old
  end
end

module FSDB

# Modex is a modal exclusion semaphore, like in syncronizer.rb.
# The two modes are shared (SH) and exclusive (EX).
# Modex is not nestable.
#
class Modex
  SH = :SH
  EX = :EX
  
  def initialize
    @waiting  = []
    @locked   = []
    @mode     = nil
    @first    = true
  end

  def try_lock mode
    Thread.critical = true
      thread = Thread.current
      if @locked.include?(thread)
        Thread.critical = false
        raise ThreadError
      end

      if @mode == mode and mode == SH and @waiting.empty? # strict queue
        @locked << thread
        rslt = true
      elsif not @mode
        @mode = mode
        @locked << thread
        rslt = true
      end
    Thread.critical = false
    rslt
  end
  
  # the block is executed in the exclusive context
  def lock mode
    Thread.critical = true
      thread = Thread.current
      if @locked.include?(thread)
        Thread.critical = false
        raise ThreadError
      end

      if @mode == mode and mode == SH and @waiting.empty? # strict queue
        @locked << thread
      elsif not @mode
        @mode = mode
        @locked << thread
      else
        @waiting << thread << mode
        Thread.stop
        Thread.critical = true
      end
      
      yield if block_given?

#      if @mode != mode
#        raise "@mode == #{@mode} but mode == #{mode}"
#      end
#
#      if @mode == EX and @locked.size > 1
#        raise "@mode == EX but @locked.size == #{@locked.size}"
#      end

    Thread.critical = false
      self
  end

  # the block is executed in the exclusive context
  def unlock
    raise ThreadError unless @mode
    
    Thread.critical = true
      yield if block_given?
      @locked.delete Thread.current
      wake_next_waiter if @locked.empty?
    Thread.critical = false

    self
  end
  
  def synchronize mode, do_when_first = nil, do_when_last = nil, arg = nil
    lock mode do
      if @first
        @first = false
        
        if do_when_first
          if mode == SH
            @mode = EX
          end

          Thread.critical = false; do_when_first[arg]; Thread.critical = true

          if mode == SH
            @mode = SH
            wake_waiting_sharers
          end
        end
      end
    end
    
    yield
    
  ensure
    unlock do
      if @locked.size == 1
        if do_when_last
          @mode = EX
          Thread.critical = false; do_when_last[arg]; Thread.critical = true
        end
        @first = true
      end
    end
  end
  
  def remove_dead # :nodoc:
    Thread.exclusive do
      waiting = @waiting; @waiting = []
      until waiting.empty?
      
        t = waiting.shift; m = waiting.shift
        @waiting << t << m if t.alive?
      end
      
      @locked = @locked.select {|t| t.alive?}
      wake_next_waiter if @locked.empty?
    end
  end

  private
  def wake_next_waiter
    first = @waiting.shift; @mode = @waiting.shift && EX
    if first
      first.wakeup
      @locked << first
    end
    first
  rescue ThreadError
    retry
  end
  
  def wake_waiting_sharers
    while @waiting[1] == SH  # note strict queue order
      t = @waiting.shift; @waiting.shift
      @locked << t
      t.wakeup
    end
  rescue ThreadError
    retry
  end

  module ForkSafely
    def fork # :nodoc:
      super do
        ObjectSpace.each_object(Modex) { |m| m.remove_dead }
        yield
      end
    end
  end
end

# FSDB users who fork should include ForkSafely or FSDB itself. (The reason for
# this is that the fork may inherit some dead threads from the parent, and if
# they hold any locks, you may get a deadlock. ForkSafely modifies fork so that
# these dead threads are cleared. If you use modexes (outside of those in FSDB),
# they should be FSDB::Modexes.
module ForkSafely
  include Modex::ForkSafely
end
include ForkSafely

end # module FSDB


if __FILE__ == $0
  # Stress test is in fsdb/test/test-modex.rb. This is just to show fork usage.
  
  include FSDB::ForkSafely
  
  m = FSDB::Modex.new
  
  SH = FSDB::Modex::SH

  Thread.new { m.synchronize(SH) { sleep 1 } }

  fork do
    m.synchronize(SH) do
     puts "Didn't get here if you used standard mutex or fork."
    end
  end

  m.synchronize(SH) { puts "Got here." }

  Process.wait
end
