require 'rubygems'
begin
  require '../lib/rbuild'
rescue Exception
  raise "\n\n**** Please install rbuild gem first ! ****\n\n"
end

task :menuconfig do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.menuconfig()
end

