#!/usr/bin/env ruby

# This example shows how easy it is to specify the formats used by a database.

require 'fsdb'
require 'yaml'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', 'fsdb/formats')
db = FSDB::Database.new(dir)

mk_ext_pat = proc { |a| /\.(?:#{a.join("|")})$/i }

TEXT_EXTENSIONS     = mk_ext_pat[%w{ txt text log rbw? }]
YAML_EXTENSIONS     = mk_ext_pat[%w{ rc cfg ya?ml }]
MARSHAL_EXTENSIONS  = mk_ext_pat[%w{ obj }]
BINARY_EXTENSIONS   = mk_ext_pat[%w{ \w+ }] # png|bmp|3ds|so|dll|doc|xls...

# For example, TEXT_EXTENSIONS == /\.(?:txt|text|log|rbw?)$/i

db.formats =
  [
    FSDB::MARSHAL_FORMAT.when(/^objects\//), # everything in the objects dir
    FSDB::TEXT_FORMAT.when(TEXT_EXTENSIONS),
    FSDB::YAML_FORMAT.when(YAML_EXTENSIONS),
    FSDB::MARSHAL_FORMAT.when(MARSHAL_EXTENSIONS),
    FSDB::BINARY_FORMAT.when(BINARY_EXTENSIONS),
#    FSDB::MARSHAL_FORMAT.when(//) # if you want a default...
  ]

db['objects/x'] = ["larry", "curly", "moe"]
puts File.read(File.join(dir, 'objects/x')).inspect

db['config.rc'] = {:color => "pale green", :legs => 8, :eyes => 17}
puts File.read(File.join(dir, 'config.rc'))

db['binary-string.exe'] = "\r\n\000abc"
puts File.open(File.join(dir, 'binary-string.exe'), "rb").read.inspect
  # the BINARY_FORMAT prevents newline conversion on Windows. Other than that,
  # it's just a string.

db['objects/foo.exe'] = ["larry", "curly", "moe"]
puts File.read(File.join(dir, 'objects/foo.exe')).inspect
  # Note that the first matching format is used.

p db.find_format('objects/foo.exe').name
