#
# RBuild: a Linux KBuild like configure/build system by Ruby DSL.
#
# Copy right(C) 2008, Ricky Zheng <ricky_gz_zheng@yahoo.co.nz>
#
# Licence: GNU GPLv2
#
# http://rbuild.sourceforge.net/
#

# reserved keys:
#   :RBUILD_SYS_CONFIG_FILE, for load/save rbuild config file.
#   :RBUILD_PLUGIN_XXXX, for rbuild plugins.

require 'fileutils'
require 'yaml'
require File.dirname(__FILE__) + '/rbuild_menuconfig'
require File.dirname(__FILE__) + '/plugins/rbuild_export_c'

module RBuild

  DEFAULT_CONFIG_FILE = '.config'
  DEFAULT_LOG_FILE = 'rbuild.log'

  class RConfig
  
    include Menuconfig
    include Export_C_Header
 
    def initialize(rconfig_file = nil)
      @conf = {}
      @current = {:type => :menu, 
            :key => :RBUILD_TOP_GLOBAL,
            :title => "Welcom to RBuild Configuration System !",
            :children => [],
            :value => true,
            :depends =>[],
            }
      @current[:parent] = @current[:key]			
      @conf[@current[:key]] = @current
      @nodes = [@current]
      @stack = []
      @deferrers = {} # deferrer node setting value, |node, value|
      
      @dirstack = []
      @top_worker_path = File.expand_path(Dir.pwd)
      @top_rconfig_path = @top_worker_path
      @curpath = @top_worker_path
      log_to_file(nil)
      
      if rconfig_file
        unless File.exist?(rconfig_file)
          puts "RConfig file: #{abs_file_name(rconfig_file)} doesn't exist ?"
        else
          @top_rconfig_path = File.expand_path(File.dirname(rconfig_file))
          exec_rconfig_file rconfig_file
        end
      end
      @deferrers.each {|node, value| set_node_value(node, value) }
    end
    
    def abs_file_name(name)
      File.expand_path(File.dirname(name)) + '/' + File.basename(name)
    end
    
    def top_node
      @conf[:RBUILD_TOP_GLOBAL]
    end
  
    # load config from file.
    # if file is nil, search the @conf[:RBUILD_SYS_CONFIG_FILE], use [:value] as file name.
    def load_config(config_file = nil)
      cfg_file_node = @conf[:RBUILD_SYS_CONFIG_FILE]
      if cfg_file_node && cfg_file_node[:no_export]
        config_file ||= cfg_file_node[:value].to_s
      end
      config_file ||= RBuild::DEFAULT_CONFIG_FILE
      return unless File.exist?(config_file)
      
      cfg = YAML.load_file(config_file)
      @conf = cfg[:conf]
      @current = top_node()
      @nodes = []
      @conf.each do |key, node|
        @nodes << node
      end
      @stack = []
      footer_msg "config loaded from: #{config_file}"
    end
  
    # save config to file.
    # if file is nil, search the @conf[:RBUILD_SYS_CONFIG_FILE], use [:value] as file name.
    def save_config(config_file = nil)
      cfg_file_node = @conf[:RBUILD_SYS_CONFIG_FILE]
      if cfg_file_node && cfg_file_node[:no_export]
        config_file ||= cfg_file_node[:value].to_s
      end
      config_file ||= RBuild::DEFAULT_CONFIG_FILE
      File.open(config_file, "w") do |f|
        cfg = { 
                :conf => @conf,
              }
        YAML.dump cfg, f
      end
      footer_msg "config saved to: #{config_file}"
    end  
  
    # ----------- RBuild DSL APIs ---------
  
    def menu(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:type => :menu, :key => key, :value => true, :title => desc}
      process_node(@conf[key], node, block)
    end
  
    def group(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:type => :group, :key => key, :value => true, :title => desc}
      process_node(@conf[key], node, block)
    end
  
    def choice(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:type => :choice, :key => key, :value => nil, :title => desc}
      process_node(@conf[key], node, block)
    end
  
    def config(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:type => :config, :key => key, :value => false, :title => desc}
      process_node(@conf[key], node, block)
    end
  
    def depends(*keys)
      keys.each {|key| @current[:depends] << key}
    end
    
    def select(*keys)
      keys.each {|key| @current[:selects] << key}
    end
    
    def unselect(*keys)
      keys.each {|key| @current[:unselects] << key}
    end    
  
    def help(desc)
      @current[:help] = desc
    end
    
    def title(desc)
      @current[:title] = desc
    end
    
    def default(value)
      @deferrers[@current] = value
    end
    
    def no_export
      @current[:no_export] = true
    end
  
    def range(*arg)
      return if arg.size == 0
      if arg.size == 1
        if arg[0].is_a?(Range) || arg[0].is_a?(Hash) || arg[0].is_a?(Array)
          @current[:range] = arg[0]
        else
          error "Invalid range setting for '#{@current[:title]}'"
        end
      else
        @current[:range] = arg        
      end
    end
    
    def source(dest)
      Dir.glob(dest).each do |fn|
        exec_rconfig_file(fn)
      end
    end
    
    # ----------------------------------------------------------------------------------------------
    private
    
    def exec_rconfig_file(fn)
      File.open(fn) do |f|
        @dirstack.push @curpath
        @curpath = File.expand_path(File.dirname(fn))
        Dir.chdir(@curpath)
        begin
          eval f.read
        rescue SyntaxError => e
          error "RConfig file syntax error?"
          error "from file: #{abs_file_name(@curpath + '/' + File.basename(fn))}"
          # error "Backtrace: #{e.backtrace.join("\n")}"
        end
        @curpath = @dirstack.pop
        Dir.chdir(@curpath)
      end
    end
    
    # conver the args to key,desc pair
    # so you can pass parameters like:
    #    :KEY => "desc"
    # or :KEY, "desc"
    # or :KEY
    # to menu/choice/config/group
    def args_to_key_desc(args)
      if args.size == 1
        if args[0].is_a?(Hash)
          h = args[0]
          key = args[0].keys[0]
          desc = args[0][key]
        else
          key = args[0]
          desc = key.to_s
        end
      elsif args.size == 2
        key, desc = args[0], args[1]
      else
        warning "Invalid parameters on: #{@current[:title]}"
      end
      return key, desc
    end    
    
    # process node's select/unselect instruction
    def process_sel_unsel(node)
      node[:selects].each {|sel| do_select(node, sel)}
      node[:unselects].each {|sel| do_unselect(node, sel)}
    end
    
    def search_ancestor(node, key)
      worker = node
      while worker && worker != top_node()
        if worker[:key] == key
          return worker
        end
        worker = @conf[worker[:parent]]
      end
      return nil
    end
    
    def do_select(node, key)
      if @conf[key].nil?
        warning "Can't not select #{key} from '#{node[:title]}', not exist?"
      else
        # search up to the top, to prevent select/unselect ancestors
        set_node_yes(@conf[key]) unless search_ancestor(node, key)
      end
    end
    
    def do_unselect(node, key)
      if @conf[key].nil?
        warning "Can't not unselect #{key} from '#{node[:title]}', not exist?"
      else
        # search up to the top, to prevent select/unselect ancestors
        set_node_no(@conf[key]) unless search_ancestor(node, key)
      end
    end
    
    def log_to_file(desc)
      log_file = @top_worker_path + '/' + DEFAULT_LOG_FILE
      if desc
        File.open(log_file, "a+") do |f|
          f.puts desc
        end
      else
        FileUtils.rm(log_file) if File.exist?(log_file)
      end
    end
    
    def warning(desc)
      puts desc
      log_to_file desc
      # STDIN.getc
    end
    
    def error(desc)
      puts desc
      log_to_file desc
      puts " -- press ENTER key continue --"
      STDIN.getc
    end
  
    def process_node(old, node, block)
      if old
        @stack.push @current
        @current = old
        block.call if block
        @current = @stack.pop                        
      else
        @nodes << node
        node[:children] ||= []
        node[:depends] ||= []
        node[:selects] ||= []
        node[:unselects] ||= []
        node[:depends] << @current[:key] if @current[:key]
        @current[:children] << node[:key]
        node[:parent] = @current[:key]
        @stack.push @current
        @conf[node[:key]] = node
        @current = node
        block.call if block
        @current = @stack.pop
      end
    end

    # search plugin config keys from @conf, if found, call plugin.
    # the plugin name is part of config key: RBUILD_PLUGIN_XXX
    # if file is provided, use file as file name, otherwise use
    # the value of @conf[:RBUILD_PLUGIN_XXX][:value]
    def export(file = nil)
      @conf.each do |key, node|
        if node[:no_export] && key.to_s =~ /RBUILD_PLUGIN_(.*)/
          plugin = $1.downcase
          @dirstack << @curpath
          @curpath = @top_rconfig_path
          Dir.chdir @curpath
          
          begin
            s = "#{plugin}('#{file || node[:value].to_s}')"
            eval s
          rescue
            error "Fail to call plugin: #{plugin}, file name: #{file || node[:value].to_s}, cmd: #{s}"
          end
          Dir.chdir @dirstack.pop
        end
      end
    end
  
    def show_all_nodes
      puts "Nodes total: #{@nodes.size}"
      @nodes.each do |n|
        puts "  Node: #{n[:key]}"
        puts "    type   : #{n[:type]}"
        puts "    value  : #{n[:value]}" 
        s =  "    depends: "
        if n[:depends].size > 0
          n[:depends].each { |d| s += "#{d}," }
        else
          s += "no"
        end
        puts s
        s =  "   children: "
        if n[:children].size > 0
          n[:children].each { |child| s += "#{@conf[child][:key]}," }
        else
          s += "no"
        end
        puts s + "\n\n"
      end
    end
  
    def show_config
      puts "Current configurations:"
      @conf.each do |key, n|
        puts "  #{n[:key]} => #{n[:value]}"
      end
    end
  
    def windows?
      RUBY_PLATFORM =~ /win/
    end

    # set node's value, the value must not be 'false' or 'nil'
    def set_node_value(node, value)
      if value
        if node[:type] == :choice && node[:value] != value
          process_sel_unsel(node)
          if node[:children].size > 0
            node[:children].each do |child|
              if child == value
                node[:value] = value
                set_node_yes(@conf[child])
              else
                set_node_no(@conf[child])  
              end
            end
          else
            node[:value] = value
          end
        end
        parent = @conf[node[:parent]]
        if parent[:type] == :choice && parent[:value] != node[:key]
          set_node_value(parent, node[:key])
        end
      end      
    end
    
    # set the node's value to {yes}
    def set_node_yes(node)
      if node_no?(node)
        if node[:type] == :config
          node[:value] = value_of_yes(node)
          process_sel_unsel(node)
          parent = @conf[node[:parent]]
          if parent[:type] == :choice
            set_node_value(parent, node[:key])
          end
        end
      end
    end
    
    # set the node's value to {no}
    def set_node_no(node)
      if node_yes?(node)
        node[:value] = value_of_no(node)
        process_sel_unsel(node)
        if node[:type] == :config
          parent = @conf[node[:parent]]
          if parent[:type] == :choice && parent[:value] == node[:key]
            set_node_no(parent)
          end
        elsif node[:type] == :choice
          node[:value] = nil
          node[:children].each do |child|
             set_node_no(@conf[child])
          end
        end
      end
    end
    
    # node's value is {yes} ?
    def node_yes?(node)
      if node[:type] == :choice
        return node[:value] != value_of_no(node)
      else
        (node[:value] || (node[:value] != value_of_no(node))) ? true : false
      end
    end
    
    # node's value is {no} ?
    def node_no?(node)
      if node[:type] == :choice
        node[:value].nil?
      else
        (node[:value].nil? || (node[:value] == value_of_no(node))) ? true : false
      end
    end
    
    def value_of_yes(node)
      true
    end
    
    def value_of_no(node)
      if node[:type] == :choice
        nil
      else
        false
      end
    end
    
    # toggle node's value
    # if the node's value is {yes} or {value}, change to {no}
    # if the node's value is {no}, change to {yes}
    def toggle_node(node)
      if node_yes?(node)
        set_node_no(node)
      else
        set_node_yes(node)
      end  
    end
  
    # get the viewable nodes under 'parent'
    # will append to the 'list_nodes' if given
    def get_list_nodes(parent, list_nodes = [], level = 1)
      children = parent[:children]
      if children
        children.each do |child|
          depok = true
          node = @conf[child]
          node[:depends].each do |dep|
            dep_node = @conf[dep]
            unless dep_node
              # can't find depend node ??, stop searching dependancy
              depok = false
              break;
            else
              # for :config, dep_node must not {no}
              # for :choice, dep_node must no {no} except dep_node is the direct parent.
              if (dep_node[:type] == :config && node_no?(dep_node)) ||
                  (dep_node[:type] == :choice && node_no?(dep_node) && (node[:parent] != dep_node[:key]))
                depok = false
                break # stop searching dependancy
              end
            end
          end
  
          if depok
            if node[:type] == :group
              list_nodes << {:node => node, :level => level}
              get_list_nodes(node, list_nodes, level + 1)
            else
              list_nodes << {:node => node, :level => level}
            end
          end
        end
      end
      list_nodes
    end

    # check whether there are any conflit/invalid default setting.  
    def check_defaults
      @nodes.each do |node|
        if node[:type] == :choice
          if node[:value] && node[:children].size > 0
            children = node[:children]
            found = nil
            children.each do |child|
              if child == node[:value]
                found = @conf[child]
                break
              end
            end
            if found
              children.each do |child|
                @conf[child][:value] = false
              end
              found[:value] = true
            else
              warning "'#{node[:title]}' default value \"#{node[:value]}\" is invalid !"
            end
          end
        end
      end
    end
    
    def footer_msg(msg = nil)
      @footer_msg = msg if msg
      @footer_msg
    end
    
    def footer_add(msg)
      @footer_msg ||= ""
      @footer_msg += ("\n" + msg)
    end
    
    def footer_clear()
      @footer_msg = nil
    end

  end

  
end

if __FILE__ == $0
  rconf = RBuild::RConfig.new('../example/RConfig')
  rconf.menuconfig()
end
