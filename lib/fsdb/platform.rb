module FSDB
  PLATFORM_IS_WINDOWS = !!(RUBY_PLATFORM =~ /win32|mingw32/)
  
  winnt = false

  if PLATFORM_IS_WINDOWS
    # Thanks to Daniel Berger and Moonwolf. See ruby-talk:90276.

    require "Win32API"

    buf = [148].pack("L")+"\0"*144
    b = Win32API.new('kernel32','GetVersionExA','P','I').call(buf)
    if b != 0
      (size,major,minor,build,platform,version)=buf.unpack("LLLLLA128")
      if platform >= 2
        winnt = true
      end
    else
      raise "Cannot detect Windows version"
    end

  end

  PLATFORM_IS_WINDOWS_NT = winnt
  PLATFORM_IS_WINDOWS_ME = PLATFORM_IS_WINDOWS && !PLATFORM_IS_WINDOWS_NT
end

