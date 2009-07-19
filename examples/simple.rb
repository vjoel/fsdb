# Run the first time without args to populate the db.
#
# Run again with any arg and it will print the contents of the db.

require 'fsdb'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/simple")

db = FSDB::Database.new dir

if ARGV.empty?
  db['foo'] = ['this', 'is', :foo, [1, 2, 3]] # create file foo, in Marshal fmt
  db['bar'] = {:bar => :baz}                  # create file bar, in Marshal fmt
  puts "Objects created. Run again with any arg to display them."
else
  p db['foo']
  p db['bar']
end
