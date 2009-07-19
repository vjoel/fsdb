#!/usr/bin/env ruby

# This example, along with client.rb, shows how to expose a FSDB::Database
# over a drb connection. Of course, you may not want to expose all methods
# of the Database, in which case you would use a more limited object that
# delegates to it.

require 'drb'
require 'fsdb'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/server")
uri = ARGV.shift || "druby://localhost:9300"

db = FSDB::Database.new(dir)

DRb.start_service(uri, db)
puts "Serving #{db.dir} at #{DRb.uri}."
puts '[interrupt] to exit.'
sleep
