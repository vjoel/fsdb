require 'fsdb'

dir ='~/tmp/fsdb/rb-format'
db = FSDB::Database.new(dir)

RUBY_FORMAT =
  FSDB::Format.new(
    /\.rb$/i,
    :name => "RUBY_FORMAT",
    :load => proc {|f| eval "proc {#{f.read}}"},
    :dump => proc {|string, f| f.syswrite(string)}
  )

db.formats = [ RUBY_FORMAT ]

db['some-script.rb'] = "|x| 1+2+x"
p db['some-script.rb'][3]
