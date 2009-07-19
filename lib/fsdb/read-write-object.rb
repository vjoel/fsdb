#!/usr/bin/ruby

# based on drb.rb

class IO
  def write_object(obj)
    str = Marshal.dump(obj)
    packet = [str.size].pack('N') + str
    write(packet)
  end
  
  # returns nil at eof
  def read_object
    sz = read(4)	# sizeof (N)
    return nil if sz.nil?
    raise TypeError, "incomplete header, size == #{sz.size}" if sz.size < 4
    sz = sz.unpack('N')[0]
    str = read(sz)
    raise TypeError, 'incomplete object' if str.nil? || str.size < sz
    Marshal::load(str)
  end
end

if __FILE__ == $0

  f = File.open('/tmp/foo', 'w')

  f.write_object([1,2,3])

  f.close

  f = File.open('/tmp/foo', 'r')

  p f.read_object

end
