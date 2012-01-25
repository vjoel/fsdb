require 'fsdb'
require 'tmpdir'

data = FSDB::Database.new "data"

formats = [
  FSDB::TEXT_FORMAT.when(/\.txt$|\.html$/),
  FSDB::BINARY_FORMAT.when(/\.png$/)
]

data.formats = formats

Dir.mktmpdir do |dir|
  #dir = "tmp1" # for testing, use a dir that won't be deleted
  
  tmp = FSDB::Database.new(dir)
  tmp.formats = formats
  
  tmp["hello.txt"] = "contents of hello.txt"
  tmp["web/snippet.html"] = "<h1>Fix this!</h1>"
  
  img = tmp.subdb("img")
  img["hello.png"] = data["hello.png"]
  img["hi.png"] = data["hello.png"]
end

# you can automatically serialize objects in yaml, json, or marshal:
require 'yaml'
require 'json'

Dir.mktmpdir do |dir|
  #dir = "tmp2" # for testing, use a dir that won't be deleted

  tmp = FSDB::Database.new(dir)
  json_format = FSDB::Format.new(
    /\.json$/, /\.js$/,
    :name => "JSON_FORMAT",
    :load => proc {|f| JSON.load(f)},
    :dump => proc {|object, f| f.syswrite(JSON.dump(object))}
  )
  tmp.formats = formats + [FSDB::YAML_FORMAT, json_format]
  
  tmp["a.yaml"] = {:some => ["complex", Object]}
  tmp["b.json"] = ["foo", 2, 3]
end
