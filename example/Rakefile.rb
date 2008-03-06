require 'scripts/rbuild'

task :menuconfig do
  rconf = RBuild::RConfig.new 'RConfig'
  rconf.menuconfig()
end

