module FSDB

# Extends FSDB:Databases to have methods for validating and normalizing paths, 
# path globbing, directory traversal, making links, ...

module PathUtilities

  # Attempts to convert a path to a canonical form so that
  # '/foo/bar', 'foo/bar', 'foo//bar', and 'foo/zap/../bar' all result in
  # the same path. The canonical form is the simplest.
  #
  # Doesn't remove trailing '/', which indicates directory.
  #
  # This is *not* necessary for database access, it's just for display
  # purposes and for validation.
  def canonical(path)
    path = path.dup
    while path.gsub!(/[^\/]+\/+\.\.(?=\/)/, ""); end
    path.gsub!(/\/\/+/, "/")
    path.gsub!(/\/\.\//, "/")
    path.sub!(/^\/+/, "")
    path
  end
  
  # Is the path in the simplest, canonical representation?
  def canonical?(path)
    path == canonical(path)
  end
  
  # Does the path refer to an object within the database?
  # This doesn't check for links.
  def valid?(path)
    canonical(path) !~ /\.\./
  end
  
  class InvalidPathError < StandardError; end

  # Raises InvalidPathError if canonical(path) still has embedded '..', which
  # means the path would refer to a file not below the database directory.
  # Returns the canonical path, otherwise.
  def validate(path)
    path = canonical(path)
    unless valid?(path)
      raise InvalidPathError, "Path #{path} is outside the database."
    end
    path
  end
  
  # Dir globbing. Excludes '.' and all '..*' files (but includes '..*/*', if
  # included in the match). Returns sorted array of strings to help avoid
  # deadlock when doing nested transactions. Does not yield to block (as
  # Dir.glob does) because #glob operates under Thread.exclusive, because it
  # uses Dir.chdir, which is not threadsafe.
  def glob(str)
    raise ArgumentError, "Block not supported for #glob" if block_given?
    Thread.exclusive do
      Dir.chdir(@dir) do
        Dir.glob(str).reject { |e| e =~ /(?:^\.$|\.\.[^\/]*$)/ }.sort!
      end
    end
  end
  
  # Use this to check whether a path yielded by an iterator is a directory.
  def directory?(path)
    /\/$/ =~ path
  end

end
  
module DirectoryIterators
  
  # +path+ should be either a directory or a file that
  # contains an object whose each method yields file names.
  def browse_dir path = "/"
    browse path do |entries|
      entries.each do |entry|
        yield File.join(path, entry)
      end
    end
  end
  
  def edit_dir path = "/"
    edit path do |entries|
      entries.each do |entry|
        yield File.join(path, entry)
      end
    end
  end
  
  def browse_each_child path = "/"
    browse_dir path do |child_path|
      browse child_path do |child_object|
        yield child_path, child_object
      end
    end
  end
  
  def edit_each_child path = "/"
    browse_dir path do |child_path|
      edit child_path do |child_object|
        yield child_path, child_object
      end
    end
  end

  def replace_each_child path = "/"
    browse_dir path do |child_path|
      replace child_path do |child_object|
        yield child_path, child_object
      end
    end
  end

  def delete_each_child path = "/"
    edit_dir path do |child_path|           # note edit_dir
      delete child_path do |child_object|
        yield child_path, child_object
      end
    end
  end

end

class Database
  include PathUtilities
  include DirectoryIterators
  
  # Create a hard link, using File.link. The names are relative to the
  # database's path.
  def link(old_name, new_name)
    File.link(absolute(old_name), absolute(new_name))
  end
  
  # Create a symbolic link, using File.symlink. The names are relative to the
  # database's path.
  def symlink(old_name, new_name)
    File.symlink(absolute(old_name), absolute(new_name))
  end
  
end

# Include this module in your database class, or extend your database object
# with it to enable checking of:
#
# - use of valid paths
#
module DatabaseDebuggable

  # Raises PathUtilities::InvalidPathError unless path is valid, in the
  # sense of #valid?.
  def must_be_valid(path)
    unless valid?(path)
      raise PathUtilities::InvalidPathError,
            "DebugDatabase noticed that #{path} is not valid."
    end
  end

  def browse(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end

  def edit(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end

  def replace(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end

  def insert(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end

  def delete(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end

  def fetch(path, *args, &block) # :nodoc:
    must_be_valid(path)
    super(path, *args, &block)
  end
end

include PathUtilities

end # module FSDB

if __FILE__ == $0
  include FSDB::PathUtilities

  p FSDB.validate("foo/zap/../bar")
  p FSDB.validate("/foo/bar")
  p FSDB.validate("foo//bar")
  p FSDB.validate("foo/zap//../../foo/bar")
  p FSDB.validate("/foo//zap/baz/../../bar")
  
  begin
    FSDB.validate("foo/../../bar")
  rescue FSDB::InvalidPathError => e
    puts e
  end

end
