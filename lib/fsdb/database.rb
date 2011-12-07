require 'fileutils'
require 'fsdb/platform'
require 'fsdb/mutex'
require 'fsdb/modex'
require 'fsdb/file-lock'
require 'fsdb/formats'

module FSDB
include Formats

FSDB::VERSION = "0.6.1"

# A thread-safe, process-safe object database class which uses the
# native file system as its back end and allows multiple file formats.

class Database
  include Formats
  
  # in seconds, seems to be large enough for all platforms (the fraction >1
  # is empirically chosen to make the tests pass--I guess that ensures that
  # the OS has had enough time to update mtime in the inode)
  if PLATFORM_IS_WINDOWS
    # On windows, FAT mtime granularity is 2 sec, NTFS is 1 sec.
    MTIME_RESOLUTION          = 2.1
  else
    # Even when linux mounts FAT, the mtime granularity is 1 sec.
    MTIME_RESOLUTION          = 1.1
  end
    
  # in seconds, adjust as needed for stability on NFS
  CLOCK_SKEW                = 0.0

  class CacheEntry #:nodoc:
    
    attr_reader :version
    attr_accessor :file_handle
    
    TIME_DELTA = Database::MTIME_RESOLUTION + Database::CLOCK_SKEW
    
    def initialize
      @mutex      = Mutex.new
      @modex      = Modex.new
      @users      = 0
      
      stale!
    end
    
    # Yields to block that loads the object, if needed.
    # Called between #start_using and #stop_using.
    def object(mtime)
      @mutex.synchronize do
        if @object and mtime == @mtime
          if @check_time - mtime < TIME_DELTA
            # If we last checked the file during the same second as mtime, the
            # file might have been touched after we checked it, so we may have
            # to load it again. (Assume resolution of file mtime <= 1.)
            @check_time = Time.now
            yield @version
          end
        else
          @check_time = Time.now
          yield nil
        end

        @object
      end
    end
    
    def just_gimme_the_damn_object!
      @object
    end
    
    def stale!
      @check_time = nil
      @mtime      = nil
      @version    = nil
      @object     = nil
    end
    
    def update(new_mtime, version, object)
      # only called in @mutex or object_exclusive context, so no need to lock
      @check_time = new_mtime
      @mtime      = new_mtime
      @version    = version
      @object     = object
    end
    
    def start_using; Thread.exclusive {@users += 1}; end
    def stop_using;  Thread.exclusive {@users -= 1}; end

    # called in context of lock on db's cache_mutex, which is also
    # required for start_using.
    def unused?;    @users == 0; end
    
    # Protects object during #browse, #edit, and so on. Should be locked
    # as long as the object is being used. It's ok to lock the @mutex
    # within the context of a lock on @modex.
    def sync_object_shared do_when_first, do_when_last
      @modex.synchronize(Modex::SH, do_when_first, do_when_last, self) { yield }
    end
    
    def sync_object_exclusive
      @modex.synchronize(Modex::EX) { yield }
    end
    
  end
  
  # Subclasses can change the defaults.
  DEFAULT_META_PREFIX       = '..fsdb.meta.'
  DEFAULT_LOCK_TYPE         = :flock
    
  # These must be methods of File.
  LOCK_TYPES                = [:flock] # obsolete: :fcntl_lock
  
  @cache = {}                   # maps <file id> to <CacheEntry>
  @cache_mutex = Mutex.new      # protects access to @cache hash

  class << self
    attr_reader :cache, :cache_mutex # :nodoc:
  end
  
  def cache; Database.cache; end
  def cache_mutex; Database.cache_mutex; end
  
  # The root directory of the db, to which paths are relative.
  attr_reader :dir
  
  # The lock type of the db, by default <tt>:flock</tt>.
  attr_reader :lock_type
  
  # Create a new database object that accesses +dir+. Makes sure that the
  # directory exists on disk, but doesn't create or open any other files.
  # The +opts+ hash can include:
  #
  # <tt>:lock_type</tt>::   <tt>:flock</tt> by default
  #
  # <tt>:meta_prefix</tt>:: <tt>'..fsdb.meta.'</tt> by default
  #
  # <tt>:formats</tt>::     nil by default, so the class's FORMATS is used
  #
  def initialize dir, opts = {}
    @dir = File.expand_path(dir)

    @lock_type = opts[:lock_type] || DEFAULT_LOCK_TYPE
    unless LOCK_TYPES.include? @lock_type
      raise "Unknown lock type: #{lock_type}"
    end
    
    @meta_prefix = opts[:meta_prefix] || DEFAULT_META_PREFIX

    @formats = opts[:formats]
    
    FileUtils.makedirs(@dir)
  end
  
  # Shortcut to create a new database at +path+.
  def Database.[](path)
    new(path)
  end
  
  # Create a new database object that accesses +path+ relative to the database
  # directory. A process can have any number of dbs accessing overlapping dirs.
  # The cost of creating an additional db is very low; its state is just the
  # dir and some options. Caching is done in structures owned by the Database
  # class itself.
  def subdb path
    self.class.new(File.join(@dir, path),
      :lock_type => @lock_type,
      :meta_prefix => @meta_prefix,
      :formats => @formats && @formats.dup
    )
  end
  
  def inspect; "#<#{self.class}:#{dir}>"; end
  
  # Convert a relative path (relative to the db dir) to an absolute path.
  def absolute(path)
    abs_path = File.expand_path(File.join(@dir, path))
    if File.directory?(abs_path)
      abs_path << ?/ # prevent Errno::EINVAL on UFS
    end
    abs_path
  end
  alias absolute_path_to absolute
  
  # Raised on attempt to access a regular file with a path ending in '/'
  class NotDirError < StandardError; end
  
  if PLATFORM_IS_WINDOWS
    def _get_file_id(abs_path) # :nodoc:
      File.stat(abs_path) # just to generate the right exceptions
      abs_path # might not be unique, due to links, etc.
    end
  else
    def _get_file_id(abs_path) # :nodoc:
      s = File.stat(abs_path) # could use SystemVIPC.ftok instead
      [s.dev, s.ino]
    end
  end

  # Convert an absolute path to a unique key for the cache, raising
  # MissingFileError if the file does not exist.
  def get_file_id(abs_path)
    _get_file_id(abs_path)
  rescue Errno::ENOTDIR
    # db['x'] = 0; db.edit 'x/' do end
    raise NotDirError
  rescue Errno::ENOENT
    raise MissingFileError, "Cannot find file at #{abs_path}"
  rescue Errno::EINTR
    retry
  end
  
  # Raised when a file cannot be created, as in:
  #
  #   db['x/'] = 0
  #
  class CreateFileError < StandardError; end
  
  # Raised when some component of a path is not a dir, as in:
  #
  #   db['x'] = 1; db['x/y'] = 2
  #
  class PathComponentError < StandardError; end
  
  # Convert an absolute path to a unique key for the cache, creating the file
  # if it does not exist. Raises CreateFileError if it can't be created.
  def make_file_id(abs_path)
    dirname = File.dirname(abs_path)
    begin
      FileUtils.makedirs(dirname)
    rescue Errno::EEXIST
      raise PathComponentError
    end
    begin
      _get_file_id(abs_path)
    rescue Errno::EINTR
      retry
    end
  rescue Errno::ENOTDIR
    # db['x'] = 0; db.replace 'x/' do end
    raise NotDirError
  rescue Errno::ENOENT
    begin
      File.open(abs_path, "w") do |f|
        _get_file_id(abs_path)
      end
    rescue Errno::EISDIR
      raise DirIsImmutableError
    rescue Errno::EINVAL
      raise DirIsImmutableError # for windows
    rescue StandardError
      raise CreateFileError
    end
  end
  
  # For housekeeping, so that stale entries don't result in unused, but
  # uncollectable, CacheEntry objects.
  def clear_entry(file_id)
    if file_id
      cache_mutex.synchronize do
        cache_entry = cache[file_id]
        cache.delete(file_id) if cache_entry and cache_entry.unused?
      end
    end
  end
  
  # Can be called occasionally to reduce memory footprint, esp. if cached
  # objects are large and infrequently used.
  def clear_cache
    cache_mutex.synchronize do
      cache.delete_if do |file_id, cache_entry|
        cache_entry.unused?
      end
    end
  end
  
private
  # Bring the object in from f, if necessary, and put it into the cache_entry.
  # Directories are not cached, since they can be changed by insert/delete.
  def cache_object(f, cache_entry)
    mtime = f.mtime
    cache_entry.object(mtime) do |cache_version|
      file_version = get_version_of(f)
      if file_version != cache_version or file_version == :directory
        cache_entry.update(mtime, file_version, load(f))
      end
    end
  end

  # used in context of read or write lock on f
  def get_version_of(f)
    path = f.path
    if path.sub!(/(?=[^\/]+$)/, @meta_prefix)
      File.open(path, "rb") do |meta|
        meta.sysread(4).unpack("N")[0]
      end
    else
      :directory
    end
  rescue
    :never_written
  end

  # used in context of write lock on f. Returns new version.
  def inc_version_of(f, cache_entry)
    path = f.path
    if path.sub!(/(?=[^\/]+$)/, @meta_prefix)
      version = cache_entry.version
      case version
      when Fixnum
        version = (version + 1) & 0x3FFFFFFF # keep it a Fixnum
      else # :never_written
        version = 0
      end

      begin
        meta = File.open(path, "wb")
      rescue Errno::EINTR
        retry
      else
        meta.syswrite([version].pack("N"))
      ensure
        meta.close
      end

      version
    else
      :directory
    end
  end

  # used in context of write lock on f
  def del_version_of(f)
    path = f.path
    if path.sub!(/(?=[^\/]+$)/, @meta_prefix)
      File.delete(path) rescue nil
    end
  end

  def use_cache_entry(file_id)
    cache_entry = nil
    cache_mutex.synchronize do
      cache_entry = cache[file_id] ||= CacheEntry.new
      cache_entry.start_using
    end
    yield cache_entry
  ensure
    cache_entry.stop_using if cache_entry
  end

  # Lock path for shared (read) use. Other threads will wait to modify it.
  def object_shared(file_id, do_when_first, do_when_last)
    use_cache_entry(file_id) do |cache_entry|
      cache_entry.sync_object_shared(do_when_first, do_when_last) do
        yield cache_entry
      end
    end
  end

  # Lock path for exclusive (write) use. Other threads will wait to access it.
  def object_exclusive(file_id)
    use_cache_entry(file_id) do |cache_entry|
      cache_entry.sync_object_exclusive do
        yield cache_entry
      end
    end
  end

  # Opens +path+ for reading ("r") with a shared lock for
  # the duration of the block. (+path+ is relative to the db.)
  def open_read_lock(path)
    abs_path = absolute(path)
    begin
      f = File.open(abs_path, "r")
    rescue Errno::EINTR
      retry
    else
      f.lock_shared(@lock_type)
      identify_file_type(f, path, abs_path)
      yield f
    ensure
      f.close if f
    end
  rescue Errno::ENOENT
    raise MissingFileError
  end

  # Raised on attempt to #edit or #replace a dir, or #insert in place of a dir.
  class DirIsImmutableError < StandardError; end
  
  # Opens +path+ for writing and reading ("r+") with an exclusive lock for
  # the duration of the block. (+path+ is relative to the db.)
  def open_write_lock(path)
    abs_path = absolute(path)
    begin
      f = File.open(abs_path, "r+")
    rescue Errno::EINTR
      retry
    else
      f.lock_exclusive(@lock_type)
      identify_file_type(f, path, abs_path)
      yield f
    ensure
      f.close if f
    end
  rescue Errno::EINVAL # for windows to pass test-fsdb.rb
    raise NotDirError
  rescue Errno::EACCES # for windows to pass test-fsdb.rb
    raise DirIsImmutableError
  rescue Errno::EISDIR
    raise DirIsImmutableError
  rescue Errno::ENOENT
    raise MissingFileError
  end

public
  
  # Raised when open_read_lock or open_write_lock cannot find the file.
  class MissingFileError < StandardError; end

  # Raised in a transaction that takes a block (#browse, #edit, #replace,
  # or #delete) to roll back the state of the object.
  class AbortedTransaction < StandardError; end ## < Exception ? Use throw?
  
  # Abort the current transaction (#browse, #edit, #replace, or #delete, roll
  # back the state of the object, and return nil from the transaction.
  #
  # In the #browse case, the only effect is to end the transaction.
  #
  # Note that any exception that breaks out of the transaction will
  # also abort the transaction, and be re-raised.
  def abort;      raise AbortedTransaction; end
  
  # Same as #abort.
  def self.abort; raise AbortedTransaction; end

  # Raised, by default, when #browse or #edit can't find the object.
  class MissingObjectError < StandardError; end

  # Called when #browse doesn't find anything at the path.
  # The original caller's block is available to be yielded to.
  def default_browse(path)
    object_missing(path) {|x| yield x}
  end

  # Called when #edit doesn't find anything at the path.
  # The original caller's block is available to be yielded to.
  def default_edit(path)
    object_missing(path) {|x| yield x}
  end
  
  # The default behavior of both #default_edit and #default_browse. Raises
  # MissingObjectError by default, but it can yield to the original block.
  def object_missing(path)
    raise MissingObjectError, "No object at #{path} in #{inspect}"
  end
  
  # Called when #fetch doesn't find anything at the path.
  # Default definition just returns nil.
  def default_fetch(path); nil; end
  
  #-- Transactions --

  # Note: "path" argument is always relative to database dir.
  # See fsdb/util.rb for path validation and normalization.
  
  # Browse the object. Yields the object to the caller's block, and returns
  # the value of the block.
  #
  # Changes to the object are not persistent, but should be avoided (they
  # *will* be seen by other threads, but only in the current process, and
  # only until the cache is cleared). If you return the object from the block,
  # or keep a reference to it in some other way, the object will no longer be
  # protected from concurrent writers.
  def browse(path = "/")                # :yields: object
    abs_path = absolute(path)
    file_id = get_file_id(abs_path)
    
    ## put these outside method, and pass in params?
    do_when_first = proc do |cache_entry|
      raise if cache_entry.file_handle

      begin
        if PLATFORM_IS_WINDOWS_ME
          abs_path.sub!(/\/+$/, "")
        end
        f = File.open(abs_path, "r")
      rescue Errno::ENOENT
        raise MissingFileError
      rescue Errno::EINTR
        retry
      end

      cache_entry.file_handle = f
      f.lock_shared(@lock_type)
      identify_file_type(f, path, abs_path)
        ## could avoid if cache_object says so
      object = cache_object(f, cache_entry)
    end
    
    do_when_last = proc do |cache_entry|
      # last one out closes the file
      f = cache_entry.file_handle
      if f
        f.close
        cache_entry.file_handle = nil
      end
    end
    
    object_shared(file_id, do_when_first, do_when_last) do |cache_entry|
      object = cache_entry.just_gimme_the_damn_object!
      yield object if block_given?
    end
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue MissingFileError
    if PLATFORM_IS_WINDOWS_ME and File.directory?(abs_path)
      raise if File::CAN_OPEN_DIR
      raise unless File.directory?(abs_path) ### redundant!
      yield Formats::DIR_LOAD_FROM_PATH[abs_path] if block_given?
    end
    clear_entry(file_id)
    default_browse(path) {|x| yield x if block_given?}
  rescue AbortedTransaction
  rescue Errno::EACCES
    raise if File::CAN_OPEN_DIR
    raise unless File.directory?(abs_path)
    # on some platforms, opening a dir raises EACCESS
    yield Formats::DIR_LOAD_FROM_PATH[abs_path] if block_given?
  end
  
  # Edit the object in place. Changes to the yielded object made within
  # the caller's block become persistent. Returns the value of the block.
  # Note that assigning to the block argument variable does not change
  # the state of the object. Use destructive methods on the object.
  def edit(path = "/")
    abs_path = absolute(path)
    file_id = get_file_id(abs_path)
    object_exclusive file_id do |cache_entry|
      open_write_lock(path) do |f|
        object = cache_object(f, cache_entry)
        result = yield object if block_given?
        dump(object, f)
        cache_entry.update(f.mtime, inc_version_of(f, cache_entry), object)
        result
      end
    end
  rescue DirIsImmutableError
    raise DirIsImmutableError, "Cannot edit dir #{path} in #{inspect}"
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue MissingFileError
    raise DirIsImmutableError if PLATFORM_IS_WINDOWS_ME and
            File.directory?(abs_path)
    clear_entry(file_id)
    default_edit(path) {|x| yield x if block_given?}
  rescue AbortedTransaction
    clear_entry(file_id) # The cached object may have edits which are not valid.
    nil
  rescue Exception
    clear_entry(file_id)
    raise
  end
  
  # Replace the yielded object (or nil) with the return value of the block.
  # Returns the object that was replaced. No object need exist at +path+.
  #
  # Use replace instead of edit when accessing db over a drb connection.
  # Use replace instead of insert if the path needs to be protected while
  # the object is prepared for insertion.
  #
  # Note that (unlike #edit) destructive methods on the object do not
  # persistently change the state of the object, unless the object is
  # the return value of the block.
  def replace(path)
    abs_path = absolute(path)
    file_id = make_file_id(abs_path)
    object_exclusive file_id do |cache_entry|
      open_write_lock(path) do |f|
        old_object = f.stat.zero? ? nil : cache_object(f, cache_entry)
        object = yield old_object if block_given?
        dump(object, f)
        cache_entry.update(f.mtime, inc_version_of(f, cache_entry), object)
        old_object
      end
    end
  rescue DirIsImmutableError
    raise DirIsImmutableError, "Cannot replace dir #{path} in #{inspect}"
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue AbortedTransaction
    clear_entry(file_id) # The cached object may have edits which are not valid.
    nil
  rescue FormatError
    clear_entry(file_id)
    File.delete(abs_path)
    raise
  rescue PathComponentError
    raise PathComponentError, "Some component of #{path} in #{inspect} " +
        "already exists and is not a directory"
  rescue CreateFileError
    raise CreateFileError, "Cannot create file at #{path} in #{inspect}"
  rescue MissingFileError
    if PLATFORM_IS_WINDOWS_ME and File.directory?(abs_path)
      raise DirIsImmutableError
    else
      raise NotDirError
    end
  rescue Exception
    clear_entry(file_id)
    raise
  end

  # Insert the object, replacing anything at the path. Returns the object.
  # (The object remains a <i>local copy</i>, distinct from the one which will be
  # returned when accessing the path through database transactions.)
  #
  # If +path+ ends in "/", then object is treated as a collection of key-value
  # pairs, and each value is inserted at the corresponding key under +path+.
  # (You can omit the "/" if the dir already exists.)
  ### is this still true?
  def insert(path, object)
    abs_path = absolute(path)
    file_id = make_file_id(abs_path)
    object_exclusive file_id do |cache_entry|
      open_write_lock(path) do |f|
        dump(object, f)
        cache_entry.update(f.mtime, inc_version_of(f, cache_entry), object)
        object
      end
    end
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue FormatError
    File.delete(abs_path)
    raise
  rescue PathComponentError
    raise PathComponentError, "Some component of #{path} in #{inspect} " +
        "already exists and is not a directory"
  rescue CreateFileError
    if PLATFORM_IS_WINDOWS_ME and /\/$/ =~ path
      raise DirIsImmutableError
    else
      raise CreateFileError, "Cannot create file at #{path} in #{inspect}"
    end
  rescue MissingFileError
    raise DirIsImmutableError if PLATFORM_IS_WINDOWS_ME
  ensure
    clear_entry(file_id) # no one else can get this copy of object
  end
  alias []= insert
  
  # Raised on attempt to delete a non-empty dir.
  class DirNotEmptyError < StandardError; end
  
  # Delete the object from the db. If a block is given, yields the object (or
  # nil if none) before deleting it from the db (but before releasing the lock
  # on the path), and returns the value of the block. Otherwise, just returns
  # the object (or nil, if none). Raises DirNotEmptyError if
  # path refers to a non-empty dir. If the dir is empty, it is deleted, and
  # the returned value is +true+. The block is not yielded to.
  # If the _load_ argument is +false+, delete the object from the db without
  # loading it or yielding, returning +true+.
  def delete(path, load=true)                  # :yields: object
    abs_path = absolute(path)
    file_id = get_file_id(abs_path)
    delete_later = false
    object_exclusive file_id do |cache_entry|
      open_write_lock(path) do |f|
        if load
          object = cache_object(f, cache_entry)
          result = block_given? ? (yield object) : object
        else
          result = true
        end
        if File::CAN_DELETE_OPEN_FILE
          File.delete(abs_path)
        else
          delete_later = true
        end
        cache_entry.stale!
        del_version_of(f)
        result
      end
    end
  rescue DirIsImmutableError
    begin
      Dir.delete(abs_path)
    rescue Errno::ENOENT
      # Someone else got it first.
    end
    true
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue MissingFileError
    if File.symlink?(abs_path) # get_file_id fails if target deleted
      File.delete(abs_path) rescue nil
    end
    if PLATFORM_IS_WINDOWS_ME and File.directory?(abs_path)
      Dir.delete(abs_path)
    end
    nil
  rescue Errno::ENOTEMPTY
    raise DirNotEmptyError, "Directory not empty - #{path} in #{inspect}"
  rescue Errno::EACCES
    raise if File::CAN_OPEN_DIR
    raise unless File.directory?(abs_path)
    # on some platforms, opening a dir raises EACCESS
    Dir.delete(abs_path)
    true
  rescue AbortedTransaction
  ensure
    if delete_later
      begin
        File.delete(abs_path) rescue Dir.delete(abs_path)
      rescue Errno::ENOENT
      end
    end
    clear_entry(file_id)
  end
  
  # Fetch a *copy* of the object at the path for private use by the current
  # thread/process. (The copy is a *deep* copy.)
  #
  # Note that this is inherently less efficient than #browse, because #browse
  # leaves the object in the cache, but, for safety, #fetch can only return a
  # copy and wipe the cache, since the copy is going to be used outside of
  # any transaction. Subsequent transactions will have to read the object again.
  def fetch(path = "/")
    abs_path = absolute(path)
    file_id = get_file_id(abs_path)
    object_exclusive file_id do |cache_entry|
      open_read_lock(path) do |f|
        object = cache_object(f, cache_entry)
        cache_entry.stale!
        object
      end
    end
  rescue NotDirError
    raise NotDirError, "Not a directory - #{path} in #{inspect}"
  rescue MissingFileError
    if PLATFORM_IS_WINDOWS_ME and File.directory?(abs_path)
      return Formats::DIR_LOAD_FROM_PATH[abs_path]
    end
    clear_entry(file_id)
    default_fetch(path)
  rescue Errno::EACCES
    raise if File::CAN_OPEN_DIR
    raise unless File.directory?(abs_path)
    # on some platforms, opening a dir raises EACCESS
    return Formats::DIR_LOAD_FROM_PATH[abs_path]
  end
  alias [] fetch
  
  #-- IO methods --
  
  # Returns object read from f (must be open for reading).
  def load(f)
    f.format.load(f)
  end
  
  # Writes object to f (must be open for writing).
  def dump(object, f)
    f.format.dump(object, f)
  end
  
  # Subclasses can define their own list of formats, with specified search order
  FORMATS = [TEXT_FORMAT, MARSHAL_FORMAT].freeze

  def formats
    @formats || self.class::FORMATS
  end
  
  def formats=(fmts)
    @formats = fmts
  end
  
  # Raised when the database has no format matching the path.
  class FormatError < StandardError; end
  
  # +path+ is relative to the database, and initial '/' is ignored
  def identify_file_type(f, path, abs_path = absolute(path))
    format = find_format(path, abs_path)
    unless format
      raise FormatError, "No format found for path #{path.inspect}"
    end
    f.binmode if format.binary?
    f.format = format
  end
  
  def find_format(path, abs_path = absolute(path))
    if DIR_FORMAT === abs_path
      DIR_FORMAT
    else
      path = path.sub(/^\//, "") # So that db['foo'] and db['/foo'] are same
      formats.find {|fmt| fmt === path}
    end
  end
  
end

end # module FSDB
