trap 'INT' do
  puts "Parent trap"
end

if false

  fork do
    trap "INT" do
      puts "Child trap"
    end
    sleep
  end
  
  Process.wait

else

  thread = Thread.new do
    system %{
      ruby -e 'trap "INT" do
        puts "Child trap"
      end
      sleep'
    }
  end

  thread.join

end

# same behavior on linux, solaris7, qnx6
