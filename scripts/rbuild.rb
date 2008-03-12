#
# RBuild: a Linux KBuild like configure/build system by Ruby DSL.
#
# Copy right(C) 2008, Ricky Zheng <ricky_gz_zheng@yahoo.co.nz>
#
# Licence: GNU GPLv2
#
# http://rbuild.sourceforge.net/
#

# Reserved keys:
#   :RBUILD_SYS_CONFIG_FILE, for load/save rbuild config file.
#   :RBUILD_PLUGIN_XXXX, for rbuild plugins.

require 'fileutils'
require 'yaml'

require File.dirname(__FILE__) + '/rbuild_menuconfig'
Dir.glob File.dirname(__FILE__) + '/plugins/*.rb' do |plugin|
  require File.dirname(__FILE__) + '/plugins/' + File.basename(plugin, '.rb')
end

require File.dirname(__FILE__) + '/rbuild_menuconfig'

module RBuild

  DEFAULT_CONFIG_FILE = 'rb.config'
  DEFAULT_LOG_FILE = 'rbuild.log'

  class RConfig
  
    include Menuconfig
    #include Export_C_Header
 
    def initialize(rconfig_file = nil)
      @conf = {}
      @current = {:id => :menu, 
            :key => :RBUILD_TOP_GLOBAL,
            :title => "Welcom to RBuild Configuration System !",
            :children => [],
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
      
      @targets = []       # target files
      @targets_cache = {} # cache the targets
      @target_deps = {}   # target depend symbols
      @target_flags = {}  # target special flags
      
      log_to_file(nil) # just delete the log file
      
      if rconfig_file
        unless File.exist?(rconfig_file)
          warning "RConfig file: #{abs_file_name(rconfig_file)} doesn't exist ?"
        else
          @top_rconfig_path = File.expand_path(File.dirname(rconfig_file))
          exec_rconfig_file rconfig_file
        end
      end
      @deferrers.each {|node, value| set_node_value(node, value) }
    end
    
    # turn file name with absolute path file name
    def abs_file_name(name)
      File.expand_path(File.dirname(name)) + '/' + File.basename(name)
    end
    private :abs_file_name
    
    # return the 'top node'
    def top_node
      @conf[:RBUILD_TOP_GLOBAL]
    end
  
    # load config from file.
    # if file is nil, search the @conf[:RBUILD_SYS_CONFIG_FILE], use [:value] as file name.
    def load_config(config_file = nil)
      cfg_file_node = @conf[:RBUILD_SYS_CONFIG_FILE]
      if cfg_file_node && cfg_file_node[:no_export]
        config_file ||= get_node_value(cfg_file_node).to_s
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
  
    def get_node_value(node)
      case node[:id]
      when :config
        if node[:range] && node[:range].is_a?(Array) && node[:range].size == 2
          if node[:hit]
            node[:range][1]
          else
            node[:range][0]
          end
        else
          node[:hit] ? node[:value] : nil
        end
      when :choice
        if node[:hit]
          if node[:children].size > 0
            value = nil
            node[:children].each do |child|
              if @conf[child][:hit]
                value = get_node_value(@conf[child])
                break
              end
            end
            value
          else
            node[:value]
          end
        else
          nil
        end
      else
        node[:title]
      end
    end
    private :get_node_value
    
    # save config to file.
    # if file is nil, search the @conf[:RBUILD_SYS_CONFIG_FILE], use [:value] as file name.
    def save_config(config_file = nil)
      cfg_file_node = @conf[:RBUILD_SYS_CONFIG_FILE]
      if cfg_file_node && cfg_file_node[:no_export]
        config_file ||= get_node_value(cfg_file_node).to_s
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
      node = {:id => :menu, :key => key, :title => desc}
      process_node(node, block)
    end
  
    def group(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:id => :group, :key => key, :title => desc}
      process_node(node, block)
    end
    
    def choice(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:id => :choice, :key => key, :value => nil, :title => desc, :hit => false}
      process_node(node, block)
    end
  
    def config(*args, &block)
      key, desc = args_to_key_desc(args)
      node = {:id => :config, :key => key, :title => desc, :hit => false, :value => nil }
      process_node(node, block)
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
    
    def hidden
      @current[:hidden] = true
    end
    
    def hex
      @current[:hex] = true
    end
    
    def string
      @current[:string] = true
    end
    
    def bool
      @current[:bool] = true
    end
    
    def digi
      @current[:digi] = true
    end
  
    # set :choice or :config node value range
    # range can be:
    #  - Range, in this case, Range type would be Fixnum
    #  - Array, in this case, range type is defined by Array elements
    #  - Hash{value1 => desc1, value2 => desc2, ...}, in this case, range is multiple choice
    #  - Array of Hash{value => desc}, use this to appoint the order. in this case, range is multiple choices
    def range(*arg)
      return if arg.size == 0
      if arg.size == 1
        if arg[0].is_a?(Range) || arg[0].is_a?(Hash) || arg[0].is_a?(Array)
          @current[:range] = arg[0]
        else
          error "Invalid range setting for '#{@current[:title]}'"
        end
      else
        @current[:range] = arg # range is Array
      end
    end
    
    # load other 'RConfig' file from dest
    # dest can be:
    #     path_to_next_rconfig/RConfig
    # or:
    #     */RConfig   ==> search any sub folders
    # or:
    #     **/RConfig  ==> reclusivly search any sub folders
    def source(dest)
      Dir.glob(dest).each do |fn|
        exec_rconfig_file(fn)
      end
    end
    
    # arg could be:
    #  - Symbols only:
    #   property :no_export, :hidden, :string
    #  - Hash:
    #   property :title => "Hello", :help => "this is a test"
    #  - Symbols + Hash (only last one can be Hash)
    #   property :no_export, :hidden, :string, :title => "Hello", :help => "this is a test"
    def property(*arg)
      arg.each do |a|
        if a.is_a?(Symbol)
          invoke_dsl a
        elsif a.is_a?(Hash)
          a.each do |key, value|
            invoke_dsl key, value
          end
        else
          warning "unsupported property type ! (of \"#{a}\", on \"#{@current[:title]}\")"
        end
      end
    end
    
    # collect target files to be compiled ...
    def target(*arg)
      arg.each do |a|
        if a.is_a?(String)
          target_add a
        elsif a.is_a?(Hash)
          a.each do |depend, target|
            if target.is_a?(String)
              target_add target, depend
            elsif target.is_a?(Array)
              target.each do |t|
                target_add t, depend if t.is_a?(String)
              end
            end
          end
        else
          warning "unsupported target type ! (of \"#{a}\", on \"#{@current[:title]}\")"
        end
      end
    end
    
    def get_targets()
      targets = []
      @targets.each do |t|
        targets << t if target_dep_ok?(t)
      end
      targets
    end
    
    # ----------------------------------------------------------------------------------------------
    private
    
    def anonymous_key()
      @anonymous_idx ||= 0
      key = "ANONYMOUS_#{@anonymous_idx}".to_sym
      @anonymous_idx += 1
      key
    end
    
    def target_dep_ok?(t)
      return true unless @target_deps[t]
      @target_deps[t].each do |dep|
        node = @conf[dep]
        return false unless node_dep_ok?(node, true)
      end
      true
    end
    
    def node_dep_ok?(node, in_dep = false)
      # no such node ? dep fail !
      return false unless node
      
      # check my depends first
      node[:depends].each do |dep|
        return false unless node_dep_ok?(@conf[dep], true)
      end
      
      return true unless in_dep
      
      case node[:id]
      when :menu, :group
        return true # for :menu, :group, or :choice, if depends are ok, I'm ok.
      when :config, :choice
        return node_no?(node) ? false : true
      end
      false # unknown type ? false !
    end
    
    def target_add(target, depend = nil)
      Dir.glob(@curpath + '/' + target) do |t|
        unless @targets_cache[t]
          @targets << t
          @targets_cache[t] = true
          @target_deps[t] = []
        end
        
        case @current[:id]
        when :choice, :config
          @target_deps[t] << @current[:key] unless @target_deps[t].include?(@current[:key])
        end

        if depend
          if depend.is_a?(Array)
            depend.each {|d| @target_deps[t] << d unless @target_deps[t].include?(t) }
          else
            @target_deps[t] << depend unless @target_deps[t].include?(depend)
          end
        end
      end
    end
    
    def invoke_dsl(name, param = nil)
      name_save = name
      name = name.to_s
      if param
        if self.respond_to?(name)
          if param.is_a?(Array)
            self.send(name, *param)
          else
            self.send(name, param)
          end
        else
          @current[name_save] = param
        end
      else
        if self.respond_to?(name)
          self.send(name)
        else
          @current[name_save] = true
        end
      end
    end
    
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
      if args.size == 0
        key = anonymous_key()
        desc = ""
      elsif args.size == 1
        if args[0].is_a?(Hash)
          key = args[0].keys[0]
          desc = args[0][key]
        elsif args[0].is_a?(Symbol)
          key = args[0]
          desc = key.to_s
        elsif args[0].is_a?(String)
          key = anonymous_key()
          desc = args[0].to_s
        else
          warning "Invalid parameters on \"#{@current[:title]}\""
        end
      elsif args.size == 2
        key, desc = args[0], args[1]
      else
        warning "Invalid parameters on \"#{@current[:title]}\""
      end
      return key, desc
    end    
    
    # process node's select/unselect instruction
    def process_sel_unsel(node)
      node[:selects].each {|sel| do_select(node, sel)}
      node[:unselects].each {|sel| do_unselect(node, sel)}
    end
    
    # search in node's ancestors.
    # if there is a ancestor has 'key', return ancestor, otherwire reutrn nil
    def search_ancestor(node, key)
      worker = node
      while worker && worker != top_node()
        if key.is_a?(Array)
          return worker if key.include?(worker[:key])
        else
          return worker if key == worker[:key]
        end
        worker = @conf[worker[:parent]]
      end
      return nil
    end
    
    # node: just for reference.
    # key: the node to be selected !
    def do_select(node, key)
      if @conf[key].nil?
        warning "Can't not select \"#{key}\" from \"#{node[:title]}\", no such node ?"
      else
        # search up to the top, to prevent select/unselect ancestors
        set_node_yes(@conf[key]) unless search_ancestor(node, key)
      end
    end
    
    # node: just for reference.
    # key: the node to be unselected !
    def do_unselect(node, key)
      if @conf[key].nil?
        warning "Can't not unselect \"#{key}\" from \"#{node[:title]}\", no such node ?"
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
        FileUtils.rm_f(log_file) if File.exist?(log_file)
      end
    end
    
    # log warning message
    def warning(desc)
      log_to_file "Warning: " + desc
    end
    
    # log error message
    def error(desc)
      log_to_file "Error: " + desc
    end
  
    # process current DSL calling
    def process_node(node, block)
      old = @conf[node[:key]]
      if old # node exist ?
        @stack.push @current
        puts "node #{node[:title]}  already exist."
        getch()
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
    # the value of @conf[:RBUILD_PLUGIN_XXX]
    def export(file = nil)
      @conf.each do |key, node|
        if node[:no_export] && key.to_s =~ /RBUILD_PLUGIN_(.*)/
          plugin = $1.downcase
          @dirstack << @curpath
          @curpath = @top_rconfig_path
          Dir.chdir @curpath
          if self.methods.include?(plugin)
            self.send(plugin, file || get_node_value(node).to_s)
          else
            warning "plugin \"#{plugin}\" not installed ?"
          end
          Dir.chdir @dirstack.pop
        end
      end
    end
    
    def windows?
      RUBY_PLATFORM =~ /win/
    end

    # set node's value, the value must not be 'false' or 'nil'
    # if you want to unselect a choice, use 'set_node_no' instead
    def set_node_value(node, value)
      if value
        node[:hit] = true
        if node[:id] == :choice && node[:value] != value
          process_sel_unsel(node)
          if node[:children].size > 0
            # for :choice which have children, the value is the child's key.
            node[:children].each do |child|
              if child == value
                node[:value] = child
                set_node_yes(@conf[child])
              else
                set_node_no(@conf[child])  
              end
            end
          else
            # for :choice which don't have children, the value is the value :)
            node[:value] = value
          end
        end
        
        parent = @conf[node[:parent]]
        if parent[:id] == :choice && parent[:value] != node[:key]
          set_node_value(parent, node[:key])
        end
      end      
    end
    
    # set the node's value to {yes}
    def set_node_yes(node)
      if node_no?(node)
        if node[:id] == :config
          node[:hit] = true
          process_sel_unsel(node)
          parent = search_ancestor(node, [:choice, :config])
          if parent
            if parent[:id] == :choice
              set_node_value(parent, node[:key])
            elsif parent[:id] == :config
              set_node_yes(parent) if node_no?(parent)
            end
          end
        else
          error "Bug! why call 'set_node_yes' on a non-config node (#{node[:title]}) ?"
        end
      end
    end
    
    # set the node's value to {no}
    def set_node_no(node)
      return unless node
      if node[:id] == :menu || node[:id] == :group
        node[:children].each do |child|
          set_node_no(@conf[child])
        end
      else
        if node_yes?(node)
          node[:hit] = nil
          if node[:id] == :config
            # set parent to "no" if have a :choice parent.
            parent = search_ancestor(node, [:choice])
            if parent && parent[:value] == node[:key]
              set_node_no(parent)
            end
            # set children to "no"
            node[:children].each do |child|
               set_node_no(@conf[child])
            end
          elsif node[:id] == :choice
            node[:value] = nil
            node[:children].each do |child|
               set_node_no(@conf[child])
            end
          else
          end
        end
      end
    end
    
    # node's value is {yes} ?
    def node_yes?(node)
      node[:hit] ? true : false
    end
    
    # node's value is {no} ?
    def node_no?(node)
      node[:hit] ? false : true
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
          node = @conf[child]
          unless node.nil? || node[:hidden]
            if node_dep_ok?(node)
              if node[:id] == :group || node[:id] == :config
                list_nodes << {:node => node, :level => level}
                get_list_nodes(node, list_nodes, level + 1) if node[:children].size > 0
              else
                list_nodes << {:node => node, :level => level}
              end
            end
          end # end of child[:hidden]
        end # end of children.each
      end
      list_nodes
    end

    # check whether there are any conflit/invalid default setting.  
    def check_defaults
      @nodes.each do |node|
        if node[:id] == :choice
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

puts "__FILE__ : #{__FILE__}"
puts "$0: #{$0}"
if __FILE__ == $0
  Dir.chdir File.expand_path(File.dirname(__FILE__))
  rconf = RBuild::RConfig.new('../example/RConfig')
  rconf.menuconfig()
end
