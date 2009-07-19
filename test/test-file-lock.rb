if ARGV.delete '-p'
  require '../posixlock/posixlock'
end

$stdout.sync = true
$stderr.sync = true

Thread.abort_on_exception = true

# Apparently, locks are per descriptor. This deadlocks w/old flock, but not
# with posix (fcntl) flock:
#
File.open("/tmp/file-lock-test", "w") do |fd1|
  File.open("/tmp/file-lock-test", "r") do |fd2|
    fd1.write "from the writer 0"
    fd1.flock(File::LOCK_EX)
    fd2.flock(File::LOCK_SH)
  end
end
puts "EXITING"; exit

thread1 = Thread.new do
  100.times do |i|
    Thread.critical = true
    File.open("/tmp/file-lock-test", "w") do |fd|
      period = 0.001
      until fd.flock(File::LOCK_EX|File::LOCK_NB)
        Thread.critical = false
        sleep period
        period *= 2 if period < 1
        Thread.critical = true
      end
      puts "Got write lock"
      Thread.critical = false

      fd.write "GARBAGE "*5
      fd.rewind
      sleep 0.0001
      fd.write "from the writer #{i}"
      
      Thread.critical = true
      puts "Releasing write lock"
      fd.flock(File::LOCK_UN)
      Thread.critical = false
    end
  end
end

thread2 = Thread.new do
  100.times do
    Thread.critical = true
    File.open("/tmp/file-lock-test", "r") do |fd|
      period = 0.001
      until fd.flock(File::LOCK_SH|File::LOCK_NB)
      Thread.critical = false
        sleep period
        period *= 2 if period < 1
        Thread.critical = true
      end
      puts "Got read lock"
      Thread.critical = false

      s = fd.read
      unless s =~ /^from the writer \d+/
        raise "String was #{s.inspect}"
      end
      
      Thread.critical = true
      puts "Releasing read lock"
      fd.flock(File::LOCK_UN)
      Thread.critical = false
    end
  end
end

thread1.join
thread2.join
puts "Done."
