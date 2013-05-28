#!/usr/bin/env ruby

require 'fsdb'
require 'fsdb/nonpersistent-attr'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/examples")
$db = FSDB::Database.new dir

# test basic use without concurrency
module TestBasic

  def self.go

    db = $db

    x = [1,2,3]
    p x.object_id                   # 537816356
    x_path = 'stuff/my-array.obj'

    db[x_path] = x
    
    # same file, different path
    p db['/stuff/my-array.obj']
    p db['stuff/my-array.obj']
    p db['stuff//my-array.obj']
    
    p db[x_path].object_id          # 537816356
    p db.delete(x_path).object_id   # 537816356
    p db.delete(x_path)             # nil

    db[x_path] = x

    db.edit(x_path) do |obj|
      obj << 4
    end

    db.browse(x_path) do |obj|
      p obj                         # [1, 2, 3, 4]
    end
    
    str_path = "stuff/foo.txt"
    db.insert str_path, "This is a file of text."
    db.clear_cache
    
    rslt = db.browse str_path do |str|
      str                         
    end
    p rslt                          # "This is a file of text."
    
    rslt = db.edit str_path do |str|
      str << " Hello,"              # destructive style
      p str                         # "This is a file of text. Hello,"
    end
    p rslt                          # nil
    
    rslt = db.replace str_path do |str|
      str + " world."                # functional style
    end
    p rslt                          # "This is a file of text. Hello, world."

    File.open(File.join(db.dir, str_path)) do |f|
      p f.read                      # "This is a file of text. Hello, world."
    end
    
    db.delete(str_path)
    
    begin
      File.open(File.join(db.dir, str_path))
    rescue Errno::ENOENT
      puts "File was deleted"       # File was deleted
    end
    
    begin
      db.browse str_path do |str|
        p str                         # nil
      end
    rescue FSDB::Database::MissingObjectError => e
      puts e
    end
    
    db['../up-a-level'] = "Got outside the db dir"

    begin
      db.validate("../up-a-level")
    rescue FSDB::Database::InvalidPathError => e
      puts e
    end
    
    db['stuff/junk'] = ["hello", "world"]
    db['stuff/subdir/qwerty'] = "dummy"
    
    subdb = db.subdb('stuff/subdir')
    raise unless subdb['qwerty'] == db['stuff/subdir/qwerty']
    
    # you can browse directories!
    db.browse "stuff/" do |entries|
      entries.each do |entry|
        path = "stuff/#{entry}"
        puts "\nThe contents of #{path} is:"
        db.browse path do |obj|
          p obj
        end
      end
    end
    puts
    
    # or, more conveniently:
    db.browse_each_child "stuff/" do |child_path, child_object|
      puts "The contents of #{child_path} is: #{child_object.inspect}"
    end
    puts
    
###    db.edit_each_child "stuff/" do |child_path, child_object|
###      child_object.reverse!  # Destructive style with edit
###    end
    
    db.browse_each_child "stuff/" do |child_path, child_object|
      puts "The contents of #{child_path} is: #{child_object.inspect}"
    end
    puts
    
###    db.replace_each_child "stuff/" do |child_path, child_object|
###      child_object.reverse  # Functional style with replace
###    end
    
    db.browse_each_child "stuff/" do |child_path, child_object|
      puts "The contents of #{child_path} is: #{child_object.inspect}"
    end
    puts
    
    p db.glob("{stuff/junk,**/*.obj}")
    
    db["abort-test"] = [1,2,3]
    db.edit "abort-test" do |x|
      x << "let's cancel this entry"
      db.abort
    end
    p db["abort-test"]
    
    # hard links and symbolic links
    db['target'] = "The target of the links"
    
    db.delete 'hard_link'
    db.delete 'symbolic_link'
    
    db.link 'target', 'hard_link'
    db.symlink 'target', 'symbolic_link'
    
    puts db['hard_link']
    puts db['symbolic_link']
    
  end

end


module TestRestore

  class Bundle
    attr_accessor :x                # saved with the bundle (same file)
    nonpersistent_attr_accessor :y  # not saved
    attr_accessor :y_path           # path to y saved with the bundle

    def restore(db)

    end
  end

  def self.go
    
    db = $db

    b1_path = 'restore-test/b1.obj'
    b2_path = 'restore-test/b2.obj'

    1.times do  # just to make the vars b1 and b2 local
      b1 = Bundle.new
      b2 = Bundle.new

      b1.x = [1,2,3]
      b1.y = b2
      b1.y_path = b2_path

      b2.x = "foo bar"
      b2.y = b1
      b2.y_path = b1_path

      # insert into db
      db[b1_path] = b1
      db[b2_path] = b2
      # should not access the objects through b1 and b2 any more
    end

    db.clear_cache

    db.browse b1_path do |b1|
      db.browse b1.y_path do |y|
        b1.y = y
        db.browse y.y_path do |yy|
          b1.y.y = yy
          # now it's safe to work with the objects
          p b1
          p b1.y
        end
      end
    end

  end

end

TestBasic.go
