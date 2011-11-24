
# What is FSDB?

FSDB is a file system data base. FSDB provides a thread-safe, process-safe Database class which uses the native file system as its back end and allows multiple file formats and serialization methods. Users access objects in terms of their paths relative to the base directory of the database. It's very light weight (the per-process state of a Database, excluding cached data, is essentially just a path string, and code size is very small, under 1K lines, all ruby).

FSDB stores data at nodes in the file system. The format can vary depending on type. For example, the default file type can be read into your program as a string, but files with the .obj suffix could be read using marshal, and files with the .yaml suffix as yaml. FSDB can easily be extended to recognize other formats, both binary and text. FSDB treats directories as collections and provides directory iterator methods. Files are the atoms of transactions: each file is saved and restored as a whole. References between objects stored in different files can be persisted as path strings.

FSDB has been tested on a variety of platforms and ruby versions, and is not known to have any problems. (On WindowsME/98/95, multiple processes can access a database unsafely, because flock() is not available on the platform.) See the Testing section for details.

FSDB does not yet have any indexing or querying mechanisms, and is probably missing many other useful database features, so it is not a general replacement for RDBs or OODBs. However, if you are looking for a lightweight, concurrent object store with reasonable performance and better granularity than PStore, in pure Ruby, with a Ruby license, take a look at FSDB. Also, if you are looking for an easy way of making an existing file tree look like a database, especially if it has heterogeneous file formats, FSDB might be useful.


## Synopsis

```ruby
require 'fsdb'

db = FSDB::Database.new('/tmp/my-data')

db['recent-movies/myself'] = ["The King's Speech", "Harry Potter 7"]
puts db['recent-movies/myself'][1]              # ==> "Harry Potter 7"

db.edit 'recent-movies/myself' do |movies|
  movies << "The Muppets"
end
```


## Path names

Keys in the database are path strings, which are simply strings in the usual forward-slash delimited format, relative to the database's directory. There are some points to be aware of when using them to refer to database objects.

* Paths to directories are formed in one of two ways:

  - explicitly, with a trailing slash, as in `db['foo/']`
  
  - implicitly, as in `db['foo']` if `foo` is already a directory, or as
    in `db['foo/bar']`, which creates `foo` if it did not
    already exist.
  
* The root dir of the database is simply `/`, its child directories are
  of the form `foo/` and so on. The leading and trailing slashes are 
  both optional.

* Objects can be stored in various formats, indicated by path name. A typical
  mapping might be:

    file name | de-serialized data type
    --------- | --------------
    `foo.obj` | Marshalled data
    `foo.txt` | String
    `foo/`    | Directory (the contents is presented to the caller as a list of file and subdirectory paths that can be used in browse, edit, etc.)
    `foo.yml` | YAML data--see examples/yaml.rb
  
    New formats, which correlate filename pattern with serialization behavior,
  can be defined and plugged in to databases. Each format has its own rules for
  matching patterns in the file name and recognizing the file. Patterns can be
  anything with a #=== method (such as a regex). See lib/fsdb/formats.rb
  examples of defining formats. For examples of associating formats with
  patterns, see examples/formats.rb.

* Different notations for the same path, such as

    ```
    /foo/bar
    foo/bar
    foo//bar
    foo/../foo/bar
    ```
  
    work correctly (they access the same objects), as do paths that denote hard
  or soft links, if supported on the platform.

    Links are subject to the same naming convention as normal files with regard
  to format identification: format is determined by the path within the
  database  used to access the object. Using a different name for a link can
  be useful if you need to access the file using two different formats (e.g.,
  plain text via `foo.txt` and tabular CSV or TSV data via `foo.table` or
  whatever).

* Accessing objects in a database is unaffected by the current dir of your
  process. The database knows it's own absolute path, and path arguments to
  the Database API are interpreted relative to that. If you want to work with a
  subdirectory of the database, and paths relative to that, use Database#subdb:
  
    ``` ruby
    db = Database.new['/tmp']
    db['foo/bar'] = 1
    foo = db.subdb('foo')
    foo['bar'] # ==> 1
    ```

* Paths that are outside the database (`../../zap`) are allowed, but may or may
  not be desirable. Use #valid? and #validate in util.rb to check for them.

* Directories are created when needed. So `db['a/b/c'] = 1` creates two dirs and
  one file.

* Files beginning with `..` are ignored by fsdb dir iterators, though they
  can still be accessed in transaction operators. Some such files
  (`..fsdb.meta.<filename>`) are used internally. All others _not_
  beginning with `..fsdb` are reserved for applications to use.

    The `..fsdb.meta.<filename>` file holds a version number for
  `<filename>`, which is used along with mtime to check for changes (mtime
  usually has a precision of only 1 second). In the future, the file may also
  be used to hold other metadata. (The meta file is only created when a file is
  written to and does not need to be created in advance when using existing
  files as a FSDB.)

* util.rb has directory iterators, path globbing, and other useful tools.


## Transactions

FSDB transactions are thread-safe and process-safe. They can be nested for
larger-grained transactions; it is the user's responsibility to avoid deadlock. 

FSDB is ACID (atomic/consistent/isolated/durable) to the extent that the underlying file system is. For instance, when an object that has been modified in a transaction is written to the file system, nothing persistent is changed until the final system call to write the data to the OS's buffers. If there is an interruption (e.g., a power failure) while the OS flushes those buffers to disk, data will not be consistent. If this bothers you, you may want to use a journaling file system. FSDB does not need to do its own journaling because of the availability of good journaling file systems.

There are two kinds of transactions:
  
- A simple transfer of a value, as in `db['x']` and `db['x'] = 1`.

    Note that a sequence of such transactions is not itself a transaction, and
  can be affected by other processes and threads.

    ``` ruby
    db['foo/bar'] = [1,2,3]
    db['foo/bar'] += [4]      # This line is actually 2 transactions
    db['foo/bar'][-1]
    ```

    It is possible for the result of these transactions to be `4`. But, if
  other threads or processes are scheduled during this code fragment, the
  result could be a completely different value, or the code could raise an
  method_missing exception because the object at the path has been replaced
  with one that does not have the `+` method or the `[ ]` method.
  The four operations are each atomic by themselves, but the sequence is not.

    Note that changes to a database object using this kind of transaction cannot
  be made using destructive methods (such as `<<`) but only by
  assignments of the form `db[<path>] = <data>`. Note that `+=`
  and similar "assignment operators" can be used but are not atomic, because

    ``` ruby
    db[<path>] += 1
    ```
 
    is really
  
    ``` ruby
    db[<path>] = db[<path>] + 1
    ```
  
    So another thread or process could change the value stored at `path` while
  the addition is happening.

- Transactions that allow more complex interaction:

    ``` ruby
    path = 'foo/bar'
    db[path] = [1,2,3]

    db.edit path do |bar|
      bar += [4]
      bar[-1]
    end
    ```

    This guarantees that, if the object at the path is still `[1, 2, 3]`
  at the time of the #edit call, the value returned by the transaction will be
  4.

    Simply put, #edit allows exclusive write access to the object at the path
  for the duration of the block. Other threads or processes that use FSDB
  methods to read or write the object will be blocked for the duration of the
  transaction. There is also #browse, which allows read access shared by any
  number of threads and processes, and #replace, which also allows exclusive
  write access like #edit. The differences between #replace and #edit are:

  - #replace's block must return the new value, whereas #edit's block must
    operate (destructively) on the block argument to produce the new value.
    (The new value in #replace's block can be a modification of the old value,
    or an entirely different object.)

  - #replace yields `nil` if there is no preexisting object, whereas #edit
    calls #default_edit (which by default calls #object_missing, which by
    default throws MissingObjectError).

  - #edit is useless over a drb connection, since is it operating on a
    Marshal.dump-ed copy. Use #replace with drb.
  
    You can delete an object from the database (and the file system) with the
  #delete method, which returns the object. Also, #delete can take a block,
  which can examine the object and abort the transaction to prevent deletion.
  (The delete transaction has the same exclusion semantics as edit and
  replace.)

    The #fetch and #insert methods are aliased with `[ ]` and
  `[ ]=`.
  
    When the object at the path specified in a transaction does not exist in the
  file system, the different transaction methods behave differently:
  
  - #browse calls #default_browse, which, in Database's implementation, calls
    object_missing, which raises Database::MissingObjectError.
  
  - #edit calls #default_edit, which, in Database's implementation, calls
    object_missing, which raises Database::MissingObjectError.

  - #replace and #insert (and #[]) ignore any missing file.
  
  - #delete does nothing (if you want, you can detect the fact that the 
    object is missing by checking for nil in the block argument).
  
  - #fetch calls #default_fetch, which, in Database's implementation, returns 
    nil.

    Transactions can be nested. However, the order in which objects are locked
  can lead to deadlock if, for example, the nesting is cyclic, or two threads
  or processes request the same set of locks in a different order. One approach
  is to only request nested locks on paths in the lexicographic order of the
  path strings: "foo/bar", "foo/baz", ...

    A transaction can be aborted with Database#abort and Database.abort, after
  which the state of the object in the database remains as before the
  transaction. An exception that is raised but not handled within a
  transaction also aborts the transaction.

    Note that there is no locking on directories, but you can designate a lock
  file for each dir and effectively have multiple-reader, single writer
  (advisory) locking on dirs. Just make sure you enclose your dir operation
  in a transaction on the lock object, and always access these objects using
  this technique.

    ``` ruby
    db.browse('lock for dir') do
      db['dir/x'] = 1
    end
    ```

## Guarding against concurrency problems

- It's the user's responsibility to avoid deadlock. See above.

- If you want to fork from a multithreaded process, you should include FSDB or
  FSDB::ForkSafely. This prevents "ghost" threads in the child process from
  permanently holding locks.
  
- It is not safe to fork while in a transaction.

- A database can be configured to use fcntl locking instead of ruby's usual
  flock call. This is necessary for Linux NFS, for example. There doesn't seem
  to be any performance difference when running on a local filesystem.

## Limitations

- Transactions are not journaled. There's no commit, undo, or versioning. (You
  can abort a transaction, however.) These could be added...

## Testing

FSDB has been tested on the following platforms and file systems:

  - Linux/x86 (single and dual cpu, ext3, ext4, and reiser file systems)
  
  - Solaris/sparc (dual and quad cpu, nfs and ufs)
  
  - QNX 6.2.1 (dual PIII)
  
  - Windows 2000 (dual cpu, NTFS)
  
  - Windows ME (single cpu, FAT32)

FSDB is currently tested with ruby-1.9.3 and ruby-1.8.7.

On windows, both the mswin32 and mingw32 builds of ruby have been used with FSDB. It has never been tested with cygwin or bccwin.

The tests include unit and stress tests. Unit tests isolate individual features of the library. The stress test (called test/test-concurrency.rb) has many parameters, but typically involves several processes, each with several threads, doing millions of transactions on a small set of objects.

The only known testing failure is on Windows ME (and presumably 95 and 98). The stress test succeeds with one process and multiple threads. It succeeds with multiple processes each with one thread. However, with two processes each with two threads, the test usually deadlocks very quickly.

## Performance

FSDB is not very fast. It's useful more for its safety, flexibility, and ease of use.

- FSDB operates on cached data as much as possible. In order to be process
  safe, changing an object (with #edit, #replace, #insert) results in a dump of
  the object to the file system. This includes marshalling or other custom
  serialization to a string, as well as a #syswrite call. The file system
  buffers may keep the latter part from being too costly, but the former part
  can be costly, especially for complex objects. By using either custom marshal
  methods, or nonpersistent attrs where possible (see nonpersistent-attr.rb),
  or FSDB dump/load methods that use a faster format (e.g., plain text, rather
  than a marshalled String), this may not be so bad.

- On an 850MHz PIII under linux, with debugging turned off (-b option),
  test-concurrency.rb reports:
  
    processes | threads   | objects   | transactions per cpu second
    --------- | --------- | --------- | ---------------------------
    1         | 1         | 10        | 965
    1         | 10        | 10        | 165
    10        | 1         | 10        | 684
    10        | 10        | 10        | 122
    10        | 10        | 100       | 100
    10        | 10        | 10000     | 92

    These results are not representative of typical applications, because the
  test was designed to stress the database and expose stability problems, not
  to immitate typical use of database-stored objects. See bench/bench.rb for
  for bechmarks.

- For speed, avoid using #fetch and its alias #[]. As noted in the API docs,
  these methods cannot safely return the same object that is cached, so must
  clear out the cache's reference to the object so that it will be loaded
  freshly the next time #fetch is called on the path.
  
    The performance hit of #fetch is of course greater with larger objects,
  and with objects that are loaded by a more complex procedure, such as
  Marshal.load.
  
    You can think of #fetch as a "deep copy" of the object. If you call it
  twice, you get different copies that do not share any parts. Or you can think
  of it as File.read--it gives you an instantaneous snapshot of the file, but
  does not give you a transaction "window" in which no other thread or process
  can modify the object.

    There is no analogous concern with #insert and its alias #[]=. These methods
  always write to the file system, but they also leave the object in the cache.

- Performance is worse on Windows. Most of the delay seems to be in system,
  rather than user, code.

## Advantages

- FSDB is useful with heterogeneous data, that is, with files in varying
  formats that can be recognized based on file name.

- FSDB can be used as an interface to the file system that understands file
  types. By defining new format clases, it's easy to set up databases that
  allow:

    ``` ruby
    home['.forward'] += ["nobody@nowhere.net"]
    etc.edit('passwd') { |passwd| passwd['fred'].shell = '/bin/zsh' }
    window.setIcon(icons['apps/editor.png'])
    ```
    
- A FSDB can be operated on with ordinary file tools. FSDB can even treat
  existing file hierarchies as databases. It's easy to backup, export, grep,
  rsync, tar, ... the database. Its just files.

- FSDB is process-safe, so it can be used for *persistent*, *fault-tolerant*
  interprocess communication, such as a queue that doesn't require both
  processes to be alive at the same time. It's a good way to safely connect a
  suite of applications that share common files. Also, you can take advantage
  of multiprocessor systems by forking a new process to handle a CPU-intesive
  transaction.

- FSDB is thread-safe, so it can be used in a threaded server, such as drb. In
  fact, the FSDB Database itself can be the drb server object, allowing browse,
  replace (but not edit), insert, and delete from remote clients! (See the
  examples server.rb and client.rb.)

- FSDB can be used as a portable interface to multithreaded file locking.
  (File#flock does not have consistent semantics across platforms.)
  
- Compared with PStore, FSDB has the potential for finer granularity, and it
  scales better. The cost of using fine granularity is that referential
  structures, unless contained within individual nodes, must be based on path
  strings. (But of course this would be a problem with multiple PStores, as
  well.)

- FSDB scales up to large numbers of objects.
  
- Objects in a FSDB can be anything serializable. They don't have to inherit
  or mix in anything.
  
- By using only the file system and standard ruby libraries, installation
  requirements are minimal.

- It may be fast enough for many purposes, especially using multiple processes
  rather than multiple threads.
  
- Pure ruby. Ruby license. Free software.


## Applications

I've heard from a couple of people writing applications that use FSDB. One app
is:

- http://tourneybot.rubyforge.org


## To do

### Fix (potential) bugs

- If two FSDBs are in use in the same process, they share the cache. If they
  associate different formats with the same file, the results will be
  surprising. Maybe the cache should remember the format used and flag an error
  if it detects an inconsistency. A similar problem could happen for other
  Database attributes, like lock-type (which should probably be global).


### Features

- Should the Format objects be classes instead of just instances of Format?

- Default value and proc for Database, like Hash.

- FSDB::Reference class:

    ``` ruby
    db['foo/bar.obj'] = "some string"
    referrer = { :my_bar => FSDB::Reference.new('../foo/bar.obj') }
    db['x/y.yml'] = referrer
    p db['x/y.yml'][:my_bar]   # ==> "some string"
    ```

    Or, more like DRbUndumped:
  
    ``` ruby
    str = "some string"
    str.extend FSDB::Undumped
    db['foo/bar.obj'] = str
    referrer = { :my_bar => str }
    db['x/y.yml'] = referrer
    p db['x/y.yml'][:my_bar]   # ==> "some string"
    ```
    
    Extending with FSDB::Undumped will have to insert state in the object that
  remembers the db path at which it is stored ('foo/bar.obj' in this case).
    
- Use (optionally) weak references in CacheEntry.

- use metafiles to emulate locking on dirs?

- optionally, for each file, store a md5 sum of the raw data, so that we may
  be able to avoid Marshal.load and (after #dump) the actual write.

- optionally, do not create ..fsdb.meta.* files.

- transactions on groups of objects

  - for edit and browse, but not replace or insert. Maybe delete.

  - `db.edit [path1, path2] do |obj1, obj2| ... end`
  
    - lock order is explicit, up to user to avoid deadlock

  - and:

    ``` ruby
    db.edit_glob "foo/**/bar*/{zap,zow}" ... do |hash|
      for path, object in hash ... end
    end
    ```

- Make irb-based database shell

  - `class Database; def irb_browse(path); browse(path) {|obj| irb obj}; end; end`

    then:
    
    ```
      irb> irb db
      irb#1> irb_browse path
      ...
      ... # got a read lock for this session
      ...
      irb#1> ^D
      irb>
    ```
    
    one problem: irb defines singleton methods, so can't dump (in edit)
    
    maybe we can extend the class of the object by some module instead...

- iterator, query, indexing methods

- more formats

  - json

  - tabular data, excel, xml, ascii db, csv
  
  - SOAP marshal, XML marshal
  
  - filters for compression, encryption

- more node types
  
    .que : use IO#read_object, IO#write_object (at end of file)
           to implement a persistent queue
  
    fifo, named socket, device, ...

- interface to file attributes (mode, etc)
  
- access control lists (use meta files)


### Stability, Security, and Error Checking

- investigate using the BDB lock mechanism in place of flock.

- in transactions, if path is tainted, apply the validation of util.rb?

- detect fork in transaction

- purge empty dirs?
  
- periodically clear_cache to keep the hash size low
  
  - every Nth new CacheEntry?
  
  - should cache entries be in an LRU queue so we can purge the LRU?
  
- should we detect recursive lock attempt and fail? (Now, it just deadlocks.)
  

### Performance

- Profiling says that Thread.exclusive consumes about 20% of cpu. Also,
  Thread.stop and Thread.run when there are multiple threads. Using
  Thread.critical in places where it is safe to do so (no exceptions raised)
  instead of Thread.exclusive would reduce this to an estimated 6%.
  ((See faster-modex .rb and faster-mutex.rb.))

- Better way of waiting for file lock in the multithread case
  
  - this may be unfixable until ruby has native threads
  
- Use shared memory for the cache, so write is not necessary after edit.

  - actually, this may not make much sense

- Option for Database to ignore file locking and possibility of other writers.

- #fetch could use the cache better if the cache kept the file contents string
  as well as the loaded object. Then the #stale! call would only have to
  wipe the reference to the object, and could leave the contents string. But
  this would increase file size and duplicate the file system's own cache.

## Web site

The current version of this software can be found at http://rubyforge.org/projects/fsdb. The main git repo is at https://github.com/vjoel/fsdb.

## License

This software is distributed under the Ruby license. See http://www.ruby-lang.org.

## Author

Joel VanderWerf, mailto:vjoel@users.sourceforge.net
Copyright (c) 2003-2011, Joel VanderWerf.
