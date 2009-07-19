# Fast, flat storage based on Kirk Haines' technique.

require 'fsdb'
require 'digest/md5'

class FlatDB < FSDB::Database

  def initialize(path, depth = 2)
    raise ArgumentError, "Invalid depth #{depth} > 32" if depth > 32

    @path_from_key = {}
    @path_pat = Regexp.new("^" + "(..)"*depth)
    @depth = depth

    super(path)
  end
  
  def path_from_key(key)
    path = @path_from_key[key]
    unless path
      if @depth > 0
        path_components = Digest::MD5.hexdigest(key).scan(@path_pat).first
        path_components << key
        path = path_components.join("/")
      else
        path = key
      end
      @path_from_key[key] = path
    end
    path
  end

  def browse(key)
    super path_from_key(key)
  end

  def edit(key)
    super path_from_key(key)
  end

  def replace(key)
    super path_from_key(key)
  end

  def delete(key, load=true)
    @path_from_key.delete key ## should probably purge this hash periodically
    super path_from_key(key), load
  end

  # don't bother with #insert, #fetch, #[], #[]= since they are
  # inherently less efficient
end

db = FlatDB.new('/tmp/fsdb/flat', 2)

db.replace 'foo.txt' do
  "this is the foo text"
end

db.browse 'foo.txt' do |x|
  p x
end

# key names can have '/' in them, in which case they reference deeper subdirs
db.replace 'sub/foo.txt' do
  "this is the subdir's foo text"
end

db.browse 'sub/foo.txt' do |x|
  p x
end

require 'benchmark'

Benchmark.bm(10) do |bm|
  nfiles = 100

  [0,1,2].each do |depth|
    db = FlatDB.new("/tmp/fsdb/depth_#{depth}", depth)
    
    puts "\ndepth=#{depth}"

    bm.report "create" do
      nfiles.times do |i|
        db.replace i.to_s do  # with a filename like that, will use marshal
          i
        end
      end
    end

    bm.report "access" do
      nfiles.times do |i|
        db.browse i.to_s do |j|
          raise unless i == j
        end
      end
    end
  end
end

__END__

N=100_000
                user     system      total        real

depth=0
create     72.680000 1772.030000 1844.710000 (1853.686824)
access     55.780000  13.090000  68.870000 ( 97.170382)

depth=1
create    125.170000  24.250000 149.420000 (329.576419)
access    143.210000  12.040000 155.250000 (759.768371)

depth=2
create    263.900000  32.570000 296.470000 (1950.482468)
access    195.200000  17.250000 212.450000 (1562.214063)

# du -sk depth_0
804236  depth_0
# du -sk depth_1
804832  depth_1
# du -sk depth_2
1006408 depth_2

Output of two successive runs, first without the db files already existing (N=10000, depth=2):

$ ruby flat.rb
                user     system      total        real
create      5.270000   2.520000   7.790000 ( 41.684685)
access      2.210000   0.380000   2.590000 (  2.626480)
$ ruby flat.rb
                user     system      total        real
create      3.020000   1.930000   4.950000 (  5.954889)
access      1.830000   0.280000   2.110000 (  2.157327)

Output of two successive runs, first without the db files already existing (N=10000, depth=0):

$ ruby flat.rb
                user     system      total        real
create      2.780000  18.710000  21.490000 ( 22.292284)
access      1.800000   0.230000   2.030000 (  2.044320)
$ ruby flat.rb
                user     system      total        real
create      3.280000   2.550000   5.830000 (  6.105209)
access      1.790000   0.300000   2.090000 (  2.200052)

