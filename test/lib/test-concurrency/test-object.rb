class ConcurrencyTest

  class TestObject
    attr_accessor :x, :last_writer, :last_write_transaction
    def initialize(max_size = nil)
      if max_size
        @random_stuff = (0...rand(max_size)).to_a.reverse.map {|i| "#{i}"}
          # so the object has variable size, and initial segments look different
      end
      @x = 0 # seems to be stored after the first attr, so its position changes
             # this is almost certainly dependent on the hashing alg.
    end
    def inspect
      "<TestObject:@x = #{@x}, @last_writer = #{@last_writer}," +
      " @last_write_transaction = #{@last_write_transaction}>"
    end
    def to_s
      inspect
    end
  end

end
