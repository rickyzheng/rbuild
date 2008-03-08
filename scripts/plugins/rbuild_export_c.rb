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
# RBuild plugin for exporting configurations to C/C++ header.
#

module RBuild

  module Export_C_Header
  
    public
    
    # will be actived by :RBUILD_PLUGIN_EXP_C_HEADER 
    def exp_c_header_file(file)
      headers = []
      headers << "/* This file is created by RBuild - a KBuild like configure/build\n"
      headers << " * system implemented by ruby DSL.\n"
      headers << " * \n"
      headers << " * http://rbuild.sourceforge.net/\n"
      headers << " */\n"
      headers << "\n"
      headers << "#ifndef _RBUILD_CONFIG_H_\n"
      headers << "#define _RBUILD_CONFIG_H_\n"
      headers << "\n"
      datas = []
      @nodes.each do |node|
        unless node[:no_export] || node_no?(node)
          case node[:id]
          when :config, :choice
            s = "#define CONFIG_" + node[:key].to_s
            value = get_node_value(node)
            if value && (value.is_a?(String) || value.is_a?(Fixnum))
              s += " (#{value.to_s})"
            end
            s += "\n"
            unless node[:id] == :choice && value.nil?
              datas << s
            end
          end
        end
      end
      footers = []
      footers <<  "\n"
      footers <<  "#endif\n"
      footers <<  "\n"
      
      lines = []
      if File.exist?(file)
        File.open(file, "r") do |f|
          while line = f.gets
            if line =~ /#define\s*CONFIG_/
              lines << line
            end
          end
        end
      end

      if datas.sort == lines.sort
        footer_msg "config file not changed, skip."
      else
        footer_msg "Export C header to file: '#{file}'"
        File.open(file, "w") do |f|
          headers.each do |line| f.write line end
          datas.each do |line| f.write line end
          footers.each do |line| f.write line end
        end
      end
    end
  end
end  

