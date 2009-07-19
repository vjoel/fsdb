#!/usr/bin/env ruby

class Module
private
  def nonpersistent_attr_accessor(*attrs)
    attrs.each do |attr|
      nonpersistent_attr_reader attr
      nonpersistent_attr_writer attr
    end
  end

  def nonpersistent_attr_reader(*attrs)
    attrs.each do |attr|
      module_eval %{
        
        @@__#{attr} = {}
        
        def #{attr}
          @@__#{attr}[self]
        end
        
      }
    end
  end

  def nonpersistent_attr_writer(*attrs)
    attrs.each do |attr|
      module_eval %{
        
        @@__#{attr} = {}
        
        def #{attr}=(arg)
          @@__#{attr}[self] = arg
        end
        
      }
    end
  end
end

if __FILE__ == $0

  class Test
    nonpersistent_attr_accessor :x, :y
    attr_accessor :z
    
    def initialize x, y, z
      self.x = x
      self.y = y
      @z = z
    end
  end
  
  t = Test.new(1,2,3)
  
  p t.x, t.y, t.z
  
  u = Marshal.load(Marshal.dump(t))
  
  p u.x, u.y, u.z

end
