# Extensions to the File class for non-blocking file locking, and for
# recording a Format in the File object.

class File
  attr_accessor :format
  
  CAN_DELETE_OPEN_FILE  = !FSDB::PLATFORM_IS_WINDOWS
  CAN_OPEN_DIR          = !FSDB::PLATFORM_IS_WINDOWS
  
  LOCK_BLOCK_FIXED_VER  = "1.8.2" # Hurray!
  LOCK_DOESNT_BLOCK     = [RUBY_VERSION, LOCK_BLOCK_FIXED_VER].
    map {|s| s.split('.')}.sort[0].join('.') ==  LOCK_BLOCK_FIXED_VER

  if FSDB::PLATFORM_IS_WINDOWS_ME
    # no flock() on WinME

    def lock_exclusive lock_type    # :nodoc
    end
    
    def lock_shared lock_type   # :nodoc
    end
  
  else
    if LOCK_DOESNT_BLOCK
      # Get an exclusive (i.e., write) lock on the file.
      # If the lock is not available, wait for it without blocking other ruby
      # threads.
      def lock_exclusive lock_type
        send(lock_type, LOCK_EX)
      rescue Errno::EINTR
        retry
      end

      # Get a shared (i.e., read) lock on the file.
      # If the lock is not available, wait for it without blocking other ruby
      # threads.
      def lock_shared lock_type
        send(lock_type, LOCK_SH)
      rescue Errno::EINTR
        retry
      end

    else
      def lock_exclusive lock_type
        if Thread.list.size == 1
          begin
            send(lock_type, LOCK_EX)
          rescue Errno::EINTR
            retry
          end
        else
          # ugly hack because waiting for a lock in a Ruby thread blocks the
          # entire process
          period = 0.001
          until send(lock_type, LOCK_EX|LOCK_NB)
            sleep period
            period *= 2 if period < 1
          end
        end
      end

      def lock_shared lock_type
        if Thread.list.size == 1
          begin
            send(lock_type, LOCK_SH)
          rescue Errno::EINTR
            retry
          end
        else
          # ugly hack because waiting for a lock in a Ruby thread blocks the
          # entire process
          period = 0.001
          until send(lock_type, LOCK_SH|LOCK_NB)
            sleep period
            period *= 2 if period < 1
          end
        end
      end
    end
  end
  
end
