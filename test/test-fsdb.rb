#!/usr/bin/env ruby

require 'test/unit'

require './test.rb'

Dir.chdir('/') # just to show that the curr dir is irrelevant

LINKS_WORK = FSDB::PLATFORM_IS_WINDOWS_NT
SYMLINKS_WORK = !FSDB::PLATFORM_IS_WINDOWS # maybe cygwin?

# test basic use without concurrency

class Test_FSDB < Test::Unit::TestCase

  def initialize(*args)
    super
    @db = $db.subdb('test-fsdb')
#    raise unless @db['/'].empty?
    cleanup '/'
  end

  def test_zzz_cleanup # Argh! Test::Unit is missing a few features....
    cleanup '/'
  end

  # this is like in test-concurrency.rb -- generalize?
  def cleanup dir
    @db.browse_dir dir do |child_path|
      if child_path[-1] == ?/ ## ugh!
        cleanup(child_path)
      else
        @db.delete(child_path)
      end
    end
    @db.delete(dir)
  end
  
  def shakeup
    # in the base test class, do nothing
  end
  
  # each test_XXX is allowed to play in @db['XXX'] or @db['XXX/']
  
  def test_insert
    @db['insert'] = ["insert"]
    shakeup
    assert_equal(["insert"], @db['insert'])
  end
  
  def test_cache_equality
    obj = ["cache_equality"]
    @db['cache_equality'] = obj
    shakeup
    assert_not_equal(obj.object_id, @db['cache_equality'].object_id)
  end
  
  def test_multipath
    token = Time.now
    @db['multipath/foo/bar'] = token
    shakeup
    assert_equal(token, @db['/multipath/foo/bar'])
    assert_equal(token, @db['multipath//foo/../foo/bar'])
  end
  
  def test_delete
    @db['delete'] = :to_be_deleted
    shakeup
    @db.delete 'delete' do
      @db.abort
    end
    shakeup
    assert_equal(:to_be_deleted, @db['delete'])
    result = @db.delete 'delete'
    shakeup
    assert_equal(:to_be_deleted, result)
    assert_equal(nil, @db['delete'])
  end
  
  def test_delete_dir
    @db['delete_dir/junk'] = :to_be_deleted
    shakeup
    result = @db.delete 'delete_dir/junk'
    result = @db.delete 'delete_dir'
    assert_equal(nil, @db['delete_dir'])
  end
  
  def test_edit
    @db['edit'] = [0, 1, 2]
    @db.edit 'edit' do |obj|
      obj << 3 # destructive op
      "insignificant block value"
    end
    shakeup
    assert_equal([0, 1, 2, 3], @db['edit'])
  end

  def test_replace
    @db['replace'] = [0, 1, 2]
    @db.replace 'replace' do |obj|
      obj << 3 # destructive op
      "significant block value"
    end
    shakeup
    assert_equal("significant block value", @db['replace'])
  end
  
  def test_browse
    @db['browse'] = "browse"
    @db.browse 'browse' do |obj|
      obj.reverse! # corrupt the cache
    end
    @db.clear_cache # dump the corrupted cache
    shakeup
    assert_equal("browse", @db['browse'])
  end
  
  def test_missing_object
    assert_equal(nil, @db['missing_object'])
    assert_raises(FSDB::Database::MissingObjectError) do
      @db.browse 'missing_object' do end
    end
  end
  
  def test_invalid_path
    assert_raises(FSDB::Database::InvalidPathError) do
      @db.validate("../up-a-level")
    end
  end
  
  def test_abuse_dir
    @db['abuse_dir/x'] = 1
    assert_raises(FSDB::Database::PathComponentError) do
      @db['abuse_dir/x/y'] = 2
    end
    if FSDB::PLATFORM_IS_WINDOWS
      assert_equal(nil, @db['abuse_dir/x/y'])
      # File.open("abuse_dir/x/y") raises ENOENT, not ENOTDIR -- hard to work around
    else
      assert_raises(FSDB::Database::NotDirError) do
        @db['abuse_dir/x/y']
      end
    end
#    assert_raises(FSDB::Database::NotDirError) do
#      @db.replace('abuse_dir/x/')
#    end
    assert_raises(FSDB::Database::DirIsImmutableError) do
      @db['abuse_dir'] = 1
    end
    assert_raises(FSDB::Database::DirIsImmutableError) do
      @db.edit('abuse_dir')
    end
    assert_raises(FSDB::Database::DirIsImmutableError) do
      @db.replace('abuse_dir')
    end
    
    ## Maybe we can artificially throw this one? Is it worth it?
#    unless RUBY_PLATFORM =~ /solaris/i
#      assert_raises(FSDB::Database::DirIsImmutableError) do
#        @db['abuse_dir/z/'] = 1
#      end
#    end
  end
  
  def test_subdb
    @db['subdb/a/b/c/d/e/f'] = 1.23456
    subdb = @db.subdb('subdb/a/b/c')
    shakeup
    assert_equal(1.23456, subdb['d/e/f'])
  end
  
  def test_browse_dir
    @db['browse_dir/x'] = 1
    @db['browse_dir/y'] = 2
    @db['browse_dir/z'] = 3
    shakeup
    assert_equal(%w{x y z}, @db['browse_dir'])
    assert_equal(%w{x y z}, @db.browse('browse_dir') {|d|d})
  end
  
  def test_glob
    @db['glob/x'] = 1
    @db['glob/y/x'] = 1
    @db['glob/z'] = 1
    @db['glob/other'] = 1
    shakeup
    assert_equal(["glob/x", "glob/y/x", "glob/z"],
      @db.glob('glob/{z,**/x}').sort)
  end
  
  def test_abort
    @db['abort'] = [0,1,2]
    @db.edit "abort" do |obj|
      obj << "garbage"
      @db.abort
    end
    shakeup
    assert_equal([0,1,2], @db["abort"])
    
    @db.replace "abort" do |obj|
      obj << "garbage"
      @db.abort
      "garbage"
    end
    shakeup
    assert_equal([0,1,2], @db["abort"])
  end
  
  if LINKS_WORK
    def test_link
      @db['link/target'] = "link target"
      @db.link 'link/target', 'link/link'
      shakeup
      assert_equal("link target", @db['link/link'])
    end
  end
  
  if SYMLINKS_WORK
    def test_symlink
      @db['symlink/target'] = "symlink target"
      @db.symlink 'symlink/target', 'symlink/symlink'
      shakeup
      assert_equal("symlink target", @db['symlink/symlink'])
    end
  end
  
  def test_nested
    @db.replace 'nested/x' do |x|
      @db.replace 'nested/y' do |y|
        "y"
      end
      "x"
    end
    
    shakeup
    
    assert_equal("x", @db['nested/x'])
    assert_equal("y", @db['nested/y'])
    
    @db.browse 'nested/y' do |y|
      @db.edit 'nested/x' do |x|
        x << " edited while browsing #{y}"
      end
    end

    shakeup
    
    assert_equal("x edited while browsing y", @db['nested/x'])
    assert_equal("y", @db['nested/y'])
  end
  
end

# Test all the same stuff, but periodically clearing the cache.
class Test_FSDB_clear_cache < Test_FSDB

  def shakeup
    @db.clear_cache
  end
  
end
