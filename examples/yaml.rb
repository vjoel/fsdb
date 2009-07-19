require 'fsdb'
require 'yaml'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/yaml")

if false # either way works!
  db = FSDB::Database.new dir
  db.formats = [FSDB::YAML_FORMAT] + db.formats
else
  class YamlDatabase < FSDB::Database
    FORMATS = [FSDB::YAML_FORMAT] + superclass::FORMATS
  end
  db = YamlDatabase.new dir
end

def show(db, path)
  puts "Here's the object:"
  puts "=================="
  p db[path]
  puts "=================="
  puts

  puts "Here's the file:"
  puts "=================="
  puts File.read(File.join(db.dir, path))
  puts "=================="
  puts
end

path = 'test.yml'
db[path] = {1=>2, "foo"=>[3, :bar]}
show(db, path)

puts "After editing..."
db.edit(path) { |obj| obj["fred"] = "flintstone" }
show(db, path)

puts "Now some strings..."
path = 'string.txt'
db[path] = "This is stored as plain text."
show(db, path)

path = 'string.yml'
db[path] = "This is stored as a yaml string."
show(db, path)
