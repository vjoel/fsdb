require 'drb'
require 'fsdb'

## can we use ssl?

module FSDB
  class Server

  private
    attr_reader :name, :dir, :transactions

    def initialize name = nil, dir = nil, db_class = nil, opts = {}
      @name = name || "fsdb-server"
      @dir  = dir || name
      @db   = (db_class || Database).new(@dir, opts)

      @listening    = true
      @transactions = 0
    end
    
    # counts transactions running in the server process
    def transaction
      Thread.exclusive {@transactions += 1}
      yield
    ensure
      Thread.exclusive {@transactions -= 1}
    end
    
    def enter_admin_runlevel
      @listening = false
    end
    
    def leave_admin_runlevel
      @listening = true
    end
  
    def check_listening
      unless @listening or user.name == 'admin'
        raise "Server not listening."
      end
    end
    
  end
end
