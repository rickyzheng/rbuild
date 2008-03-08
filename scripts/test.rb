# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'io/wait'
  
def getch
  state = `stty -g`
  begin
    system "stty raw -echo cbreak isig"
    until STDIN.ready?
      sleep 0.01
    end
    sleep 0.01
    s = STDIN.read_nonblock(10)
    s.each_byte do |b|
      puts "--- #{b}"
    end
  ensure
    system "stty #{state}"
  end
  s[0]
end

while true
  c = getch()
  puts "Get a key: #{c}"
end