#!/usr/bin/env ruby

unless defined? Thread.exclusive
  class Thread # :nodoc:
    def self.exclusive
      old = critical
      self.critical = true
      yield
    ensure
      self.critical = old
    end
  end
end

module FSDB

# Mutex class based on standard thread.rb Mutex, which has some problems:
#
# - waiters are not a strict queue (try_lock can jump the queue, after
#   which the queue gets *rotated*). Race condition.
#
# - doesn't use Thread.exclusive in enough places
#
# - no way to make dead threads give up the mutex, which is crucial in a fork
#
# Note: neither this Mutex nor the one in thread.rb is nestable.
#
class Mutex
  def initialize
    @waiting = []
    @locked = nil
    @waiting.taint  # enable tainted comunication
    self.taint
  end

  def locked?
    @locked
  end

  def try_lock
    Thread.exclusive do
      if not @locked # and @waiting.empty? # not needed
        @locked = Thread.current
        true
      end
    end
  end
  
  def lock
    thread = Thread.current
    Thread.exclusive do
      if @locked
        @waiting.push thread
        Thread.stop
        unless @locked == thread
          raise ThreadError, "queue was jumped"
        end
      else
        @locked = thread
      end
      self
    end
  end

  def unlock
    return unless @locked
    
    t = Thread.exclusive { wake_next_waiter }
    
    begin
      t.run if t
    rescue ThreadError
    end
    self
  end

  def synchronize
    lock
    yield
  ensure
    unlock
  end

  def remove_dead # :nodoc:
    Thread.exclusive do
      @waiting = @waiting.select {|t| t.alive?}
      wake_next_waiter if @locked and not @locked.alive?
      ## what if @locked thread left the resource in an inconsistent state?
    end
  end

  private
  def wake_next_waiter
    t = @waiting.shift
    t.wakeup if t
    @locked = t
  rescue ThreadError
    retry
  end

  module ForkSafely
    def fork # :nodoc:
      super do
        ObjectSpace.each_object(Mutex) { |m| m.remove_dead }
        yield
      end
    end
  end
end

# FSDB users who fork should include ForkSafely or FSDB itself. If you use
# mutexes (outside of those in FSDB), they should be FSDB::Mutexes.
module ForkSafely
  include Mutex::ForkSafely
end
include ForkSafely

end # module FSDB


if __FILE__ == $0
  # Stress test is in fsdb/test/test-mutex.rb. This is just to show fork usage.
  
  include FSDB::ForkSafely
  
  m = FSDB::Mutex.new

  Thread.new { m.synchronize { sleep 1 } }

  fork do
    m.synchronize { puts "Didn't get here if you used standard mutex or fork." }
  end

  m.synchronize { puts "Got here." }

  Process.wait
end
