unless defined? Process.times
  def Process.times; Time.times; end
end

unless defined? [].any?
  module Enumerable
    def any?
      each {|x| return true if yield x}
      false
    end
  end
end

unless defined? [].inject
  module Enumerable
    def inject n
      each { |i|
        n = yield n, i
      }
      n
    end
  end
end

unless Dir.chdir {:worked} == :worked
  class << Dir
    alias old_chdir chdir
    def chdir(*args)
      if block_given?
        begin
          old_dir = Dir.pwd
          old_chdir(*args)
          yield
        ensure
          old_chdir(old_dir)
        end
      else
        old_chdir(*args)
      end
    end
  end
end
