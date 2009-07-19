require 'mkmf'

if have_func("flock")
  create_makefile 'fcntl_lock'
else
  puts "fcntl_lock option not available on this platform. Please ignore"
  puts "the error message after running 'ruby intall.rb setup' and"
  puts "proceed to the installation step, 'ruby install.rb install'."
end
