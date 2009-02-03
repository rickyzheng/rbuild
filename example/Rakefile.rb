require 'rubygems'
begin
  require 'rbuild'
rescue Exception
  begin
    load '../lib/rbuild.rb'
  rescue Exception
    raise "\n\n**** Please install rbuild gem first ! ****\n\n"
  end
end

task :menuconfig do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.menuconfig()
end

