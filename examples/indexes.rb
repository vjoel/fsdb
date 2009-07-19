require 'fsdb'
require 'yaml'
require 'rbtree'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/indexes")

db = FSDB::Database.new dir

db.formats = [
  FSDB::MARSHAL_FORMAT.when(/_index$/),
  FSDB::YAML_FORMAT.when(/^circles/)
]
# We use MARSHAL_FORMAT for the indexes because rbtree is not compatible with
# yaml, and anyway faster indexes are better.

class Circle
  attr_reader :x, :y, :radius, :name
  def initialize x, y, radius, name
    @x, @y, @radius, @name = x, y, radius, name
  end
end

{
  "c1" => Circle.new(1, 1, 2, "c1"),
  "c2" => Circle.new(5, 3, 1, "c2"),
  "c3" => Circle.new(5, 4, 1, "c3"),
  "c4" => Circle.new(-2, 10, 6, "c4"),
  "c5" => Circle.new(12, 15, 2, "c5"),
  "c6" => Circle.new(-1, -5, 3, "c6"),
}.each do |k,v|
  db["circles/#{k}"] = v
end

db.replace "radius_index" do
  radius_index = RBTree.new

  db.browse "circles" do |c_names|
    c_names.each do |c_name|
      c = db["circles/#{c_name}"]
      (radius_index[c.radius] ||= []) << c.name
    end
  end
  
  radius_index
end

# find all circles of radius between 2 and 5, inclusive

db.browse "radius_index" do |radius_index|
  radius_index.bound(2,5) do |r, c_names|
    c_names.each do |c_name|
      p db["circles/#{c_name}"]
    end
  end
end
