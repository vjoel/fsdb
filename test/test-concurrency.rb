#!/usr/bin/env ruby

$:.unshift(File.expand_path("..", __FILE__))

require 'test.rb'

require 'test-concurrency/init'
require 'test-concurrency/test-object'

module Enumerable
  unless instance_methods.include?("sum")
    def sum
      if block_given?
        inject(0) { |n, i| n + yield(i) }
      else
        inject(0) { |n, i| n + i }
      end
    end
  end
end

class ConcurrencyTest

  attr_reader :params
  attr_reader :db
    
  def run
    if @child_index
      run_child_process
    else
      manage_children
    end
  end
  
  def manage_children
    make_test_objects
    start_processes
    monitor
    
    cleanup('/') unless @params["nocleanup"]
  end
  
  def make_test_objects
    paths.each do |path|
      @db[path] = TestObject.new(@params["object size"])
    end
  end
  
  def paths
    unless @paths
      object_count  = @params["object count"]
      @paths = (0...object_count).map {|i| "TestObjects/#{i}"}
    end
    @paths
  end
  
  def start_processes
    trap 'INT' do
      @interrupted = true
    end
    processes = (0...@params["process count"]).map do |process_idx|
      run_process(process_idx)
    end
  end

  def run_process(idx)
    if @params["process count"] == 1
      Thread.new do
        run_child_process()
      end
    
    elsif params["nofork"]
      run_process_without_fork(idx)
      
    else
      begin
        fork do
          run_child_process()
        end
      rescue NotImplementedError => e
        raise unless /fork/ =~ e.message
        run_process_without_fork(idx)
      end
    end
  
  end
  
  def run_process_without_fork(idx)
    unless @ruby_name
      require 'rbconfig'

      @ruby_name = File.join(Config::CONFIG['bindir'],
                             Config::CONFIG['RUBY_INSTALL_NAME'])
    end

    cmd = "#{@ruby_name} #{$0} --child-index=#{idx} --database=#{@subdb_dir}"
    Thread.new {system cmd}
# both of these work fine.
#    IO.popen(cmd) # don't need to Process.waitpid(f.pid) -- use fsdb instead
  end
  
  def run_child_process
    @db.replace "Results/#{Process.pid}.yml" do
      profile_flag  = @params["profile"]
      process_count = @params["process count"]
      thread_count  = @params["thread count"]
      object_count  = @params["object count"]

      if process_count == 1
        srand(@params["seed"])
        profile if profile_flag
      else
        srand(Process.pid)
      end

      start_time = Process.times
      threads = (0...thread_count).map do |thread_index|
        Thread.new(thread_index) do |ti|
          thread = Thread.current
          thread[:number] = ti
          thread[:transactions] = 0
          thread[:increments] = Hash.new(0)

          begin
            run_thread(thread)
          rescue Exception
            last_msgs 50
            $stderr.puts "*** Process #{Process.pid}, thread #{ti}:"
            raise
          end
        end
      end
      
      status_thread = Thread.new do
        loop do
          sleep 1.0
          iters = threads.sum {|thread| thread[:iter]}
          @db["Status/#{Process.pid}.yml"] = {:iters => iters}
        end
      end
      
      trap 'INT' do
        @interrupted = true # just in case this is also the parent process
        threads.each do |thread|
          thread[:stop_flag] = true if thread.alive?
        end
      end

      # could start up a monitor thread here to periodically
      # update the results in the database

      threads.each { |thread| thread.join }
      status_thread.kill

      finish_time = Process.times

      utime = finish_time.utime - start_time.utime
      stime = finish_time.stime - start_time.stime
      total_transactions = threads.sum {|thread| thread[:transactions]}
      rate = total_transactions / (utime + stime)

      total_increments = Hash.new(0)
      threads.each do |thread|
        thread[:increments].each do |path, inc|
          total_increments[path] += inc
        end
      end

      {
        :utime => utime,
        :stime => stime,
        :transactions => total_transactions,
        :rate  => rate,
        :increments => total_increments
      }
    end
  end
  
  def run_thread thread
    rep_count     = @params["rep count"]
    object_size   = @params["object size"]
    max_sleep     = @params["max sleep"]
    
    max_sleep_sec = max_sleep && max_sleep/1000.0
    
    test_flag = !(@params["bench"] || @params["profile"])

    rep_count.times do |iter|
      thread[:iter] = iter
      path = paths[rand(paths.size)]
      
      break if thread[:stop_flag]

      case rand(100)

      when 0..49
        @db.browse path do |tester|
          if test_flag
            __x__ = tester.x

            sleep(rand*max_sleep_sec) if max_sleep_sec

            unless __x__ == tester.x
              fail "browse test: x == #{__x__} but tester.x == #{tester.x}"
            end
          end

          thread[:transactions] += 1
        end
      
      when 50..69
        @db.edit path do |tester|
          if test_flag
            tester.x += 1
            __x__ = tester.x

            sleep(rand*max_sleep_sec) if max_sleep_sec

            unless __x__ == tester.x
              fail "edit test: x == #{__x__} but tester.x == #{tester.x}"
            end

            tester.last_write_transaction = :EDIT
            tester.last_writer = "#{Process.pid}, #{thread[:number]}"
          else
            tester.x += 1
          end

          thread[:increments][path] += 1
          thread[:transactions] += 1
        end

      when 70..90
        @db.replace path do |tester|
          if test_flag
            tester.x += 1
            __x__ = tester.x

            sleep(rand*max_sleep_sec) if max_sleep_sec

            unless __x__ == tester.x
              fail "replace test: x == #{__x__} but tester.x == #{tester.x}"
            end

            # this is what replace lets us do:
            old_tester = tester
            tester = TestObject.new(object_size)
            tester.x = old_tester.x
            old_tester.last_write_transaction = :GARBAGE

            tester.last_write_transaction = :REPLACE
            tester.last_writer = "#{Process.pid}, #{thread[:number]}"
          else
            tester.x += 1
          end

          thread[:increments][path] += 1
          thread[:transactions] += 1

          tester # replace needs to know the new object
        end

      else
        if test_flag
          sleep(rand*max_sleep_sec) if max_sleep_sec
          @db.clear_cache
        end

      end

    end
  end
  
  def status_meter(part_done = nil)
    stats = @db.glob("Status/*").map do |stat_path|
      @db[stat_path]
    end
    
    iters = stats.sum {|stat| stat[:iters]}
    part_done ||= iters / @total_iters.to_f
    
    arrow_size = 60
    arrow = "=" * (part_done*arrow_size)
    arrow.<< ">" if part_done < 1
    
    "[%-#{arrow_size}s] %9.5f%% done" % [arrow, part_done*100]
  end
  
  def monitor
    process_count = @params["process count"]
    thread_count  = @params["thread count"]
    rep_count     = @params["rep count"]
    object_count  = @params["object count"]
    quiet         = @params["quiet"]
    
    @total_iters = process_count * thread_count * rep_count
    
    unless quiet or not $defout.isatty
      monitor_thread = Thread.new do
        loop do
          print "\r#{status_meter}"
          sleep 1.0
        end
      end
    end
    
    # wait for all processes to show up
    sleep(0.1) until @db["Results"] and @db["Results"].size == process_count
    
    results = @db.glob("Results/*").map do |res_path|
      @db[res_path] # entails waiting for it to finish
    end

    monitor_thread.kill if monitor_thread
    print "\r#{status_meter(1)}"
    
    unless results.all? {|r|r}
      tot = results.size
      bad = results.select{|r| not r}.size
      raise "Some processes (#{bad} of #{tot}) did not finish."
    end
    
    if @interrupted
      puts "\nInterrupted. Results so far:"
    else
      puts "\nRuns finished: #{process_count} processes X #{thread_count} " +
           "threads X #{rep_count} steps on #{object_count} objects "
    end
        
    total_increments = Hash.new(0)
    results.each do |result|
      result[:increments].each do |path, inc|
        total_increments[path] += inc
      end
    end

    total_increments.each do |path, inc|
      unless @db[path].x == inc
        raise "Data inconsistency: For path #{path},\n" +
              "file has #{@db[path].x} but there were #{inc} increments"
      end
    end
    
    total_transactions = results.sum {|result| result[:transactions]}
    total_utime = results.sum {|result| result[:utime]}
    total_stime = results.sum {|result| result[:stime]}
    
    total_time = total_utime + total_stime
    
    s_pct = 100 * total_stime / total_time
    
    printf "%20s: %10d\n", "Transactions", total_transactions
    printf "%20s: %13.2f sec (%.1f%% system)\n", "Time", total_time, s_pct
    printf "%20s: %13.2f tr/sec\n", "Rate", total_transactions/total_time
  end
  
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
  
end

if __FILE__ == $0
  
  ConcurrencyTest.new(ARGV).run

end
