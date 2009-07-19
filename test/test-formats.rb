#!/usr/bin/env ruby

require 'test/unit'

require './test.rb'

class Test_Formats < Test::Unit::TestCase

  PREFIX_FORMAT =
    FSDB::Format.new(/^prefix\/format\/here\//, :binary,
      :name => "PREFIX_FORMAT",
      :load => proc {|f| f.read},
      :dump => proc {|string, f| f.syswrite("PREFIX_FORMAT")}
    )

  def initialize(*args)
    super
    @db = $db.subdb('test-formats')
#    raise unless @db['/'].empty?

    @db.formats = [
      TEXT_FORMAT.when(/\.te?xt$/i, /\.string$/i), # can have two args
      YAML_FORMAT.when(/\.ya?ml$/i),
      BINARY_FORMAT.when(/\.bin$/i),
      PREFIX_FORMAT
      # No default format, so can test FormatError.
    ]
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
  
  def test_missing_format
    assert_raises(FSDB::Database::FormatError) do
      @db['foo.bar'] = 3
    end
    assert_raises(FSDB::Database::FormatError) do
      @db.replace('foo.bar') { 3 }
    end
  end
  
  def test_prefix_matching
    @db['prefix/format/here/t1'] = "dummy"
    @db['prefix/format/here/t2/t2'] = "dummy"
    shakeup
    assert_equal("PREFIX_FORMAT", @db['prefix/format/here/t1'])
    assert_equal("PREFIX_FORMAT", @db['prefix/format/here/t2/t2'])
    assert_raises(FSDB::Database::FormatError) do
      @db['prefix/format/here-not'] = 3
    end
  end
  
  def test_binary_format
    binstr = "\r\n\000\001\002a\nb\rc"
    @db['bin.bin'] = binstr
    shakeup
    assert_equal(binstr, @db['bin.bin'])
  end

  def test_zzz_cleanup # Argh! Test::Unit is missing a few features....
    cleanup '/'
  end

end

# Test all the same stuff, but periodically clearing the cache.
class Test_Formats_clear_cache < Test_Formats

  def shakeup
    @db.clear_cache
  end
  
end
