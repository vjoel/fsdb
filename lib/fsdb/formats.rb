module FSDB

  # Formats are handled as instances rather than as subclasses so that they
  # can be dynamically generated, serialized, etc. When defining a dump
  # proc for a new format, be sure to perform the write with a single syswrite
  # call to protect data consistency in case of exceptions.
  class Format
    attr_reader :name, :options, :patterns
    def initialize(*args)
      @options = []; @patterns = []; @binary = false
      while arg = args.shift
        case arg
        when Symbol
          @options << arg
          eval "@#{arg} = true"  ## yech! use instance_variable_set in 1.8
        when Hash
          @name ||= arg[:name]
          @load ||= arg[:load]
          @dump ||= arg[:dump]
        else
          @patterns << arg
        end
      end
    end
    
    attr_writer :patterns
    protected :patterns=
    
    # A convenient way to use a format for a different pattern.
    # Duplicates the format and sets the patterns to the specified patterns.
    def when(*patterns)
      fmt = dup
      fmt.patterns = patterns
      fmt
    end

    def ===(path)
      @patterns.any? {|pat| pat === path}
    end

    # Used only on Windows.
    def binary?
      @binary
    end

    def load(f)
      @load[f] if @load
    rescue Errno::EISDIR
      Formats::DIR_LOAD[f] ## any reason not to do this?
    rescue Errno::ENOTDIR
      raise Database::NotDirError
    rescue StandardError => e
      raise e,
        "Format #{name} can't load object at path #{f.path}: #{e.inspect}"
    end

    def dump(object, f, *opts)
      if @dump
        f.rewind; f.truncate(0)
        @dump[object, f]
        f.flush
      end
    rescue StandardError => e
      raise e,
        "Format #{name} can't dump object at path #{f.path}: #{e.inspect}" +
        "\n\nObject is:\n#{object.inspect[0..1000]}\n\n"
    end
  end

  module Formats

    # Files of the form '..*', as well as '.', are excluded from dir lists.
    HIDDEN_FILE_PAT = /^\.(?:$|\.)/
    
    DIR_PAT = /\/$/

    DIR_LOAD_FROM_PATH = proc do |path|
      begin
        files = Dir.entries(path).reject { |e| HIDDEN_FILE_PAT =~ e }
      rescue Errno::ENOENT
        []
      else
        Thread.exclusive do # Dir.chdir is not threadsafe
          Dir.chdir path do
            files.each do |entry|
              if not DIR_PAT =~ entry and File.directory?(entry)
                entry << ?/
              end
            end
          end
        end
      end
    end

    DIR_LOAD = proc do |f|
      path = f.path
      DIR_LOAD_FROM_PATH[path]
    end

    DIR_FORMAT = Format.new(DIR_PAT, :name => "DIR_FORMAT", :load => DIR_LOAD)

    TEXT_FORMAT =
      Format.new(
        /\.txt$/i, /\.text$/i,
        :name => "TEXT_FORMAT",
        :load => proc {|f| f.read},
        :dump => proc {|string, f| f.syswrite(string)}
      )

    # Use this for image files, native executables, etc.
    BINARY_FORMAT =
      Format.new(
        /\.jpg$/i, /\.so$/i, /\.dll$/i, /\.exe$/i, /\.bin$/i,
          # add more with the Format#when construct
        :binary,
        :name => "BINARY_FORMAT",
        :load => proc {|f| f.read},
        :dump => proc {|string, f| f.syswrite(string)}
      )

    marshal_load = proc {|f| Marshal.load(f)}
    marshal_dump = proc {|object, f| f.syswrite(Marshal.dump(object))}

    MARSHAL_FORMAT =
      Format.new(
        //, :binary,
        :name => "MARSHAL_FORMAT",
        :load => marshal_load,
        :dump => marshal_dump
      )
        # Actually, Marshal does binmode=true automatically.

    YAML_FORMAT =
      Format.new(
        /\.yml$/, /\.yaml$/,
        :name => "YAML_FORMAT",
        :load => proc {|f| YAML.load(f)},
        :dump => proc {|object, f| f.syswrite(YAML.dump(object))}
      )
      
  end

end # module FSDB
