#!/usr/bin/env ruby

# An alternative benchmark to the -b mode of test/test-concurrency.rb.

require 'fsdb'

dir = File.join(ENV['TMPDIR'] || ENV['TMP'] || 'tmp', "fsdb/bench")
@db = FSDB::Database.new(dir)

@db.formats = [
  FSDB::MARSHAL_FORMAT.when(/text$/),
  FSDB::MARSHAL_FORMAT.when(/marshal$/)
]

def db; @db; end

def bench total_transactions

  utime = stime = 0
  max = 0

  total_transactions.times do |i|
    start_time = Process.times
    yield i
    finish_time = Process.times

    delta_utime = finish_time.utime - start_time.utime
    delta_stime = finish_time.stime - start_time.stime
    
    if delta_utime + delta_stime > max
      max = delta_utime + delta_stime
    end
    
    utime += delta_utime
    stime += delta_stime
  end


  total_time = utime + stime
  s_pct = 100 * stime / total_time

  printf "%20s: %10d\n", "Transactions", total_transactions
  printf "%20s: %13.2f sec (%.1f%% system)\n", "Time", total_time, s_pct
  printf "%20s: %13.2f tr/sec\n", "Rate", total_transactions/total_time
  printf "%20s: %13.2f sec\n", "Longest", max

end

def do_single_object(reps, obj, ext)
  name = "#{ext}.#{ext}"
  puts "Writes to one #{ext} object:"
  bench reps do
    db[name] = obj
  end

  puts "Reads from one #{ext} object:"
  bench reps do
    db.browse(name) # browse is faster than fetch (alias [])
  end

  puts "Alternating writes to and reads from one #{ext} object:"
  bench reps do |i|
    if i % 2 == 0
      db[name] = obj
    else
      db.browse name
    end
  end
end

def do_sequence(reps, obj, ext, count)
  file_map = (0..count).map {|i| "#{ext}_#{i}.#{ext}"}

  puts "Writes to a sequence of #{count} #{ext} objects:"
  bench reps do |i|
    db[file_map[i % count]] = obj
  end

  puts "Reads from a sequence of #{count} #{ext} objects:"
  bench reps do |i|
    db.browse(file_map[i % count])
  end

  puts "Alternating writes to and reads from a sequence of #{count} #{ext} objects:"
  bench reps do |i|
    if i % 2 == 0
      db[file_map[i % (count/2)]] = obj
    else
      db.browse(file_map[i % ((count-1)/2)])
    end
  end
end

def do_rand_sequence(reps, obj, ext, count)
  file_map = (0..count).map {|i| "#{ext}_#{i}.#{ext}"}

  puts "Writes to a sequence of #{count} #{ext} objects in random order:"
  bench reps do |i|
    db[file_map[rand(count)]] = obj
  end

  puts "Reads from a sequence of #{count} #{ext} objects in random order:"
  bench reps do |i|
    db.browse(file_map[rand(count)])
  end

  puts "Alternating writes to and reads from a sequence of #{count} #{ext} objects in random order:"
  bench reps do |i|
    if i % 2 == 0
      db[file_map[rand(count)]] = obj
    else
      db.browse(file_map[rand(count)])
    end
  end
end

# this is like in test-concurrency.rb -- generalize?
def cleanup dir
  @db.browse_dir dir do |child_path|
    if child_path =~ /\/$/ ## ugh!
      cleanup(child_path)
    else
      @db.delete(child_path)
    end
  end
  @db.delete(dir)
end

size = 100
str = 'x'*size        # string to use in plain text objects
ary = str.split('')   # string to use in marshalled objects
reps = 100

do_single_object(reps, str, "text")
do_sequence(reps, str, "text", 100)
do_rand_sequence(reps, str, "text", 100)

do_single_object(reps, ary, "marshal")
do_sequence(reps, ary, "marshal", 100)
do_rand_sequence(reps, ary, "marshal", 100)

cleanup '/'
