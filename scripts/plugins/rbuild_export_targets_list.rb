#
# RBuild: a Linux KBuild like configure/build system by Ruby DSL.
#
# Copy right(C) 2008, Ricky Zheng <ricky_gz_zheng@yahoo.co.nz>
#
# Licence: GNU GPLv2
#
# http://rbuild.sourceforge.net/
#
#
# RBuild plugin for exporting targets list.
#

module RBuild

  class RConfig
  
    public
    
    # will be actived by :RBUILD_PLUGIN_EXP_TARGETS_LIST 
    def exp_targets_list(file)
      targets = get_targets()
      old_targets = []
      
      if File.exist?(file)
        File.open(file, "rb") do |f|
          while line = f.gets
            t = line.chomp.strip
            if t.size > 0
              old_targets << t
            end
          end          
        end
      end
      
      if targets.sort == old_targets.sort
        footer_msg "target file not changed, skip."
      else
        footer_msg "Export targets list to file: '#{file}'"
        File.open(file, "wb") do |f|
          targets.each do |t|
            f.puts t
          end
        end
      end
    end
  end
end  

