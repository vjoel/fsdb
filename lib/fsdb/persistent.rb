#!/usr/bin/env ruby

require 'thread'
require 'ftools'
require 'fsdb/file-lock'

# Mixin for an object that persists in a file by itself.
#
# References from the object to objects which need to persist separately
# should be through nonpersistent_attr_accessors. Otherwise, objects
# referred to in attrs will persist in the same file.

module Persistent

  def persistent_mutex
    @persistent_mutex ||
      Thread.exclusive do
        @persistent_mutex ||= Mutex.new  # ||= to prevent race condition
      end
  end

  # Save the persistent object (and all of its persistent references) to
  # its file. If a block is given, call it (with self) in the context of
  # locks that protect the file from other threads and processes. This can
  # be used to atomically save related objects in separate files.
  def save
    persistent_mutex.synchronize do
      File.makedirs(File.dirname(persistent_file))
      File.open(persistent_file, "wb") do |f|
        f.lock_exclusive_fsdb do
          dump(f)
          yield self if block_given?
        end
      end
    end
  end
  
  def dump(*args)
    Marshal.dump(self, *args)
  end

  def persistent_file
    raise "#{self.class} must define the #persistent_file method to" +
          " return the path of the file in which object persists."
  end

  class << self

    # Need to take care that only one thread in the process is restoring
    # a particular object, or there will be multiple copies.
    def restore file
      object = File.open(file, "rb") do |f|
        f.lock_shared_fsdb do
          load(f)
        end
      end
      object.restore file
      object
    end
    
    def load(*args)
      Marshal.load(*args)
    end
    
  end
  
  # Called when the object is loaded, allowing the object to restore some
  # state from the path at which it was saved.
  def restore file; end

end

if __FILE__ == $0

  class Foo
    include Persistent
    attr_accessor :x
    attr_accessor :dir
    def persistent_file; "/tmp/foo"; end
    def restore file; @dir = File.dirname(file); end
  end
  
  foo = Foo.new
  foo.x = 1
  foo.save
  foo.x = 2
  foo = Persistent.restore("/tmp/foo")
  p foo.x
  p foo.dir

end
