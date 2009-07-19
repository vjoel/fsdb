require 'fsdb' # http://redshift.sourceforge.net/fsdb

db = FSDB::Database.new("~/tmp")

# Tell FSDB to use YAML format when it sees ".yml" and ".yaml" suffixes.
# It is easy to extend the recognition rules to handle other formats.
db.formats = [FSDB::YAML_FORMAT] + db.formats

# Write (atomically) the initial data to the file.
db["config.yml"] = { "key1" => 111, "key2" => 222 }

# Enter a thread-safe and process-safe transaction to
# change the state of the file.
db.edit("config.yml") do |cfg|
  cfg['key1'] = 'aaa'
  cfg['key2'] = 'bbb'
end

# Check that it works.
puts File.read(File.expand_path("~/tmp/config.yml"))

__END__

Output:

--- 
key1: aaa
key2: bbb
