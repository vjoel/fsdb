require 'fsdb'
require 'yaml'

include FSDB

$stdout.sync = true
$stderr.sync = true

Thread.abort_on_exception = true

tmp_dir = ENV['TMPDIR'] || ENV['TMP'] || 'tmp'
dir = File.join(tmp_dir, 'fsdb')
$db = Database.new(dir, :lock_type => lock_type)

mk_ext_pat = proc { |a| /\.(?:#{a.join("|")})$/i }

TEXT_EXTENSIONS     = mk_ext_pat[%w{ txt text log rbw? }]
YAML_EXTENSIONS     = mk_ext_pat[%w{ cfg ya?ml }]
MARSHAL_EXTENSIONS  = mk_ext_pat[%w{ obj }]
BINARY_EXTENSIONS   = mk_ext_pat[%w{ \w+ }] # png|bmp|3ds|so|dll|doc|xls...

$db.formats =
  [
    FSDB::TEXT_FORMAT.when(TEXT_EXTENSIONS),
    FSDB::YAML_FORMAT.when(YAML_EXTENSIONS),
    FSDB::MARSHAL_FORMAT.when(MARSHAL_EXTENSIONS),
    FSDB::BINARY_FORMAT.when(BINARY_EXTENSIONS),
    FSDB::MARSHAL_FORMAT.when(//)
  ]

trap 'INT' do
  last_msgs 60
  exit!
###    require 'irb-shell'  ## for some reason the __FILE__==$0 code runs?
###    IRB.start_session($db)
end

# For testing
$eputs_msgs = []
def eputs str
  Thread.exclusive do
    $eputs_msgs <<
#    $stderr.puts \
      "Process #{Process.pid}, thread #{Thread.current[:number]} #{str}"
  end
end

def last_msgs n
  Thread.exclusive do
    $stderr.puts $eputs_msgs[-n..-1]
  end
end
