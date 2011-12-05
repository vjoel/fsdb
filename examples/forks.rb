require 'fsdb'

db = FSDB::Database.new '/tmp/fsdb-example'

db['foo.txt'] = "hello, world"
puts db['foo.txt']
puts

p1 = fork do
  puts "*** starting fork #1 at #{Time.now}"
  db.edit 'foo.txt' do |str|
    str << "\n edited by fork #1 at #{Time.now}"
    sleep 2 # give fork #2 a chance to try editing
    str << "\n done editing in fork #1 at #{Time.now}"
  end
end

sleep 1

p2 = fork do
  puts "*** starting fork #2 at #{Time.now}"
  db.edit 'foo.txt' do |str|
    str << "\n edited by fork #2 at #{Time.now}"
    str << "\n done editing in fork #2 at #{Time.now}"
  end
end

Process.waitpid p1
Process.waitpid p2

puts db['foo.txt']

__END__

hello, world

*** starting fork #1 at Tue Nov 29 11:03:03 -0800 2011
*** starting fork #2 at Tue Nov 29 11:03:04 -0800 2011
hello, world
 edited by fork #1 at Tue Nov 29 11:03:03 -0800 2011
 done editing in fork #1 at Tue Nov 29 11:03:05 -0800 2011
 edited by fork #2 at Tue Nov 29 11:03:05 -0800 2011
 done editing in fork #2 at Tue Nov 29 11:03:05 -0800 2011
