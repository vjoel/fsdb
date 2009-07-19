  require 'fsdb'
  require 'yaml'

  dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "my_data")

  db = FSDB::Database.new dir
  db.formats = [FSDB::YAML_FORMAT] + db.formats

  3.times do |i|
    db["Cat#{i}.yml"] = %w{
      name1
      name2
      name3
    }
  end

  path = "Cat1.yml"

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
