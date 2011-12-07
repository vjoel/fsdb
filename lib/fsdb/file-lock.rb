# Extensions to the File class for non-blocking file locking, and for
# recording a Format in the File object.

class File
  attr_accessor :format
  
  CAN_DELETE_OPEN_FILE  = !FSDB::PLATFORM_IS_WINDOWS
  CAN_OPEN_DIR          = !FSDB::PLATFORM_IS_WINDOWS
  
  if FSDB::PLATFORM_IS_WINDOWS_ME
    # no flock() on WinME

    def lock_exclusive lock_type    # :nodoc
    end
    
    def lock_shared lock_type   # :nodoc
    end
  
  else
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
  end
  
end
