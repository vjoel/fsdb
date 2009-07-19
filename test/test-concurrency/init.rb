require 'optparse'

class ConcurrencyTest

  def initialize(argv)
  
    # defaults
    @subdb_dir = "TestConcurrency#{Process.pid}"
    @child_index = nil

    params = {
      "object count"  => 10,
      "object size"   => nil,
      "max sleep"     => nil,
      "bench"         => false,
      "profile"       => false,
      "process count" => 2,
      "thread count"  => 2,
      "rep count"     => 1000,
      "verbose"       => false,
      "seed"          => nil,
      "nofork"        => false,
      "nocleanup"     => false,
      "quiet"         => false
    }

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] args\n\n" +
        "      args are: process_count thread_count rep_count"

      opts.separator("")
      opts.separator("  Test parameters:")
      opts.separator("")

      opts.on("--object-count COUNT", Integer,
              "number of objects (default #{params['object count'].inspect})"
             ) do |count|
        params["object count"] = count
      end

      opts.on("--object-size SIZE", Integer,
              "max size of objects (default #{params['object size'].inspect})"
             ) do |size|
        params["object size"] = size
      end

      opts.on("--max-sleep TIME", Integer,
              "max time (ms) to sleep (default #{params['max sleep'].inspect})"
             ) do |time|
        params["max sleep"] = time
      end

      opts.on("-s", "--seed SEED", Integer, "set seed to SEED") do |seed|
        srand(seed)
        params["seed"] = seed
      end

      opts.separator("")
      opts.separator("  Test modes:")
      opts.separator("")

      opts.on("-b", "--bench", "run in benchmark mode") do
        params["bench"] = true
      end

      opts.on("-p", "--profile", "run in profile mode") do
        params["profile"] = true
        require 'profile'
      end

      opts.on("--fcntl-lock", "use fcntl version of flock") do
        # actually, this arg is already picked out by test.rb
      end

      opts.on("--nofork", "do not use fork, even if available") do
        params["nofork"] = true
      end

      opts.on("--nocleanup", "do not remove the files used by the test") do
        params["nocleanup"] = true
      end

      opts.on("--quiet", "no status output") do
        params["quiet"] = true
      end

      opts.on("--verbose", "show details (such as params)") do
        params["verbose"] = true
      end

      opts.on("--child-index INDEX", Integer,
              "run as INDEX-th child processes to the main",
              "test process and ignore all other options,",
              "except --database") do |i|
        @child_index = i
      end

      opts.on("--database PATH", "use PATH for the database",
              "  path is relative to #{$db.dir}",
              "  default for this proc was:",
              "    #{@subdb_dir}"
             ) do |path|
        @subdb_dir = path
      end

      opts.separator("")

      opts.on_tail("-h", "--help", "show this message") do
        puts opts
        exit
      end
    end

    begin
      opts.parse!(argv)
      if argv.size > 3
        raise OptionParser::ParseError,
          "Too many non-option arguments: #{argv.join(' ')}"
      end
    rescue OptionParser::ParseError => e
      puts "", e.message, ""
      puts opts
      exit
    end

    unless params["seed"]
      srand()
      params["seed"] = rand(10000)
    end
    
    test_mode = !(params["bench"] || params["profile"])
    if test_mode and params["object size"] == nil
      params["object size"] = 10
    end

    count_args = argv.map{|x|x && x.to_i}
    params["process count"] = count_args[0] if count_args[0]
    params["thread count"] = count_args[1] if count_args[1]
    params["rep count"] = count_args[2] if count_args[2]

    @db = $db.subdb(@subdb_dir)

    if params["verbose"]
      $stderr.puts "Using database at #{@db.dir}"
      $stderr.puts({"Params are" => params}.to_yaml)
    end

    if @child_index
      @params = db['params.yml'] # use parent's params
    else
      db['params.yml'] = @params = params
    end
  end

end
