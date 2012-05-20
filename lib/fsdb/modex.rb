require 'thread'

module FSDB

# Modex is a modal exclusion semaphore.
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
    @m        = Mutex.new
  end

  def try_lock mode
    @m.synchronize do
      thread = Thread.current
      raise ThreadError, "nesting not allowed" if @locked.include?(thread)

      if @mode == mode and mode == SH and @waiting.empty? # strict queue
        @locked << thread
        true
      elsif not @mode
        @mode = mode
        @locked << thread
        true
      else
        false
      end
    end
  end
  
  # the block is executed in the exclusive context
  def lock mode
    @m.synchronize do
      thread = Thread.current
      raise ThreadError, "nesting not allowed" if @locked.include?(thread)

      if @mode == mode and mode == SH and @waiting.empty? # strict queue
        @locked << thread
      elsif not @mode
        @mode = mode
        @locked << thread
      else
        @waiting << thread << mode
        @m.unlock
        Thread.stop
        @m.lock
      end
      
      yield if block_given?

#      if @mode != mode
#        raise "@mode == #{@mode} but mode == #{mode}"
#      end
#
#      if @mode == EX and @locked.size > 1
#        raise "@mode == EX but @locked.size == #{@locked.size}"
#      end

      self
    end
  end

  # the block is executed in the exclusive context
  def unlock
    raise ThreadError, "already unlocked" unless @mode
    
    @m.synchronize do
      if block_given?
        begin
          yield
        ensure
          @locked.delete Thread.current
        end
      
      else
        @locked.delete Thread.current
      end
      
      wake_next_waiter if @locked.empty?
    end

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

          nonexclusive { do_when_first[arg] }

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
          nonexclusive { do_when_last[arg] }
        end
        @first = true
      end
    end
  end
  
  def remove_dead # :nodoc:
    @m.synchronize do
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
  def nonexclusive
    raise ThreadError unless @m.locked?
    @m.unlock
    yield
  ensure
    @m.lock
  end
  
  def wake_next_waiter
    first_waiter = @waiting.shift; @mode = @waiting.shift && EX
    if first_waiter
      first_waiter.wakeup
      @locked << first_waiter
    end
    first_waiter
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
