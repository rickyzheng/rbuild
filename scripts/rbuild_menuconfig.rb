

module RBuild

  module Menuconfig
  
    private
    
    KEY_SPACE = 32
    KEY_ESC = 27
    if RUBY_PLATFORM =~ /win/
      KEY_RIGHT = 77
      KEY_LEFT = 75
      KEY_UP = 72
      KEY_DOWN = 80
    else
      KEY_RIGHT = ?C
      KEY_LEFT = ?D
      KEY_UP = ?A
      KEY_DOWN = ?B
    end
    
    # conver the viewable nodes list to navable nodes list
    def list_nodes_to_navable(list)
      navable = []
      list.each do |x|
        unless x[:node][:id] == :group
          navable << x[:node]
        end
      end
      navable
    end
  
    def nav_prev(list, cur)
      navable = list_nodes_to_navable(list)
      idx = navable.index(cur)
      return cur unless idx
      return cur if idx == 0
      navable[idx-1]
    end
  
    def nav_next(list, cur)
      navable = list_nodes_to_navable(list)
      idx = navable.index(cur)
      return cur unless idx
      return cur if idx == navable.size - 1
      navable[idx+1]
    end
    
    def clear_screen()
      if windows?
        system("cls")
      else
        system("clear")
      end
    end
  
    # showing the given viewable nodes list.
    def show_list_nodes(current, cursor = nil)
      lists = get_list_nodes(current)
      navables = list_nodes_to_navable(lists)
      cursor ||= (navables[0] || current)

      clear_screen()      
      puts "=== #{current[:title]} ==="
      puts ""
      lists.each do |list|
        node = list[:node]
        level = list[:level]
        s = ""
        case node[:id]
        when :group
          s = "  " + ('-' * level) + " #{node[:title]} " + ('-' * level)
        when :menu
          s = "#{cursor == node ? ">" : " "}" + (' ' * level) + "-+-" + " #{node[:title]}" + " -+-"
        when :config
          s = "#{cursor == node ? ">" : " "}" + (' ' * level) + "[#{node[:hit] ? "*" : " "}]" + " #{node[:title]}"
        when :choice
          s = "#{cursor == node ? ">" : " "}" + (' ' * level) + "\{#{node[:hit] ? "*" : " "}\}" + " #{node[:title]}"
          if node[:hit]
            if node[:children].size > 0
              s += " <#{@conf[node[:value]][:title]}>"
            else
              s += " <#{node[:value].to_s}>"  # TODO: maybe showing desc would be better ...
            end              
          end
        end
        puts " " + s
      end
      puts ""
      show_footer_bar()
      return lists, cursor
    end
    
    
    def show_footer_bar
      puts "[[ " + footer_msg() + " ]]" if footer_msg()
      puts "--------------------------------------------"
      puts "  (S)ave   (L)oad   e(X)port   (Q)uit\n"
    end
    
    def get_dbg_key
      @dbg_idx ||= 0
      @dbg_ks ||= [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
      k = @dbg_ks[@dbg_idx]
      @dbg_idx += 1
      k
    end
    
    # read key press without echo ...
    def getch
      if windows?
        require 'Win32API'
        fun = Win32API.new("crtdll", "_getch", [], 'L')
        fun.call
      else
        require 'io/wait'
        if false && DBG_GETCH
          get_dbg_key()
        else
          state = `stty -g`
          begin
            system "stty raw -echo cbreak isig"
            until STDIN.ready?
              sleep 0.1
            end
            s = STDIN.read_nonblock(3)
          ensure
            system "stty #{state}"
          end
        end
        s[s.size - 1]
      end
    end
    
    # node value simple input, if range == nil, means string input.
    def simple_input(node, range = nil)
      clear_screen()
      puts "=== #{node[:title]} ==="
      puts ""
    
      if range
        begin
          succ = false
          value = get_node_value(node)
          if value
            print "Input < #{range.min}..#{range.max}, default:'#{value}' > : "
          else
            print "Input < #{range.min}..#{range.max} >: "
          end
          s = STDIN.gets.chomp
          if s == ""
            succ = true
          else
            value = s.to_i
            if range.include?(value)
              set_node_value(node, value)
              succ = true
            else
              puts "Invalid input, press any key try again ..."
              getch()
            end
          end
        rescue
          puts "Invalid input, press any key try again ..."
          getch()
        end until succ
      else
        # if no range privided, just input string
        begin
          if node[:value]
            print "Input < default: '#{node[:value]}' >: "
          else
            print "Input: "
          end
          s = STDIN.gets.chomp.strip
          unless s == ""
            value = get_node_value(node)
            if value
              if value.is_a?(String)
                set_node_value(node, s)
              elsif node[:value].is_a?(Fixnum)
                set_node_value(node, s.to_i)
              else
                set_node_value(node, s)
              end
            else
              set_node_value(node, s.to_i)
            end
          end
        rescue
          set_node_value(node, s) # if any error happens when calling '.to_i', use string
        end
      end
    end
    
    # node value input by choice one of the value from range (could be array or hash)
    def choice_input(node, range)
      values = []
      if range.is_a?(Array)
        if range[0].is_a?(Hash)
          range.each do |v| values << {:value => v.keys[0], :desc => v[v.keys[0]]} end
        else
          range.each do |v| values << {:value => v, :desc => v.to_s} end
        end
      elsif range.is_a?(Hash)
        range.each do |v, desc| values << {:value => v, :desc => desc} end
      end
      do_choice_input(node, values) if values.size > 0
    end
    
    # values is an array of Hash{:value =>?, :selected =>?, :desc => ?}
    def do_choice_input(node, values)
      cursor = 0
      selected = nil
      values.each_index do |idx|
        elm = values[idx]
        if get_node_value(node) == elm[:value]
          elm[:selected] = true
          selected = idx
          cursor = idx
        end
      end
      
      show_choice_input(node, values, cursor)
      while true do
        c = getch()
        case c
        when ?\r, KEY_SPACE, KEY_RIGHT, '6'[0] # ENTER, SPACE, RIGHT -->
          if selected
            if selected != cursor
              values[selected][:selected] = false
              values[cursor][:selected] = true
              selected = cursor
            else
              selected = nil
              values[cursor][:selected] = false
              set_node_no(node)
            end
          else
            selected = cursor
            values[cursor][:selected] = true
          end
        when KEY_UP,'8'[0] # UP
          cursor -= 1 if cursor > 0
        when KEY_DOWN,'2'[0] # DOWN
          cursor += 1 if cursor < values.size - 1
        when KEY_LEFT, KEY_ESC, '4'[0]
          set_node_value(node, values[selected][:value]) if selected
          break
        end
        show_choice_input(node, values, cursor)
      end      
    end

    # values is an array of Hash{:value =>?, :selected =>?, :desc => ?}
    def show_choice_input(node, values, cursor)
      clear_screen()      
      puts "=== #{node[:title]} ==="
      puts ""
      values.each_index do |idx|
        elm = values[idx]
        puts "#{cursor == idx ? ">" : " "} [#{elm[:selected] ? '*' : ' '}] #{elm[:desc]}"
      end
      puts ""
    end
    
    def node_input(node)
      if node[:range]
        if node[:range].is_a?(Range)
          simple_input(node, node[:range])
        else
          choice_input(node, node[:range])
        end
      else
        simple_input(node)
      end
    end
    
    public
    
    # start menuconfig ...
    def menuconfig()
      current = top_node()
      # STDIN.getc
      list_nodes, cursor = show_list_nodes(current)
      nav_stack = []

      while true do
        c = getch()
        footer_clear()
        case c
        when ?\r, KEY_SPACE, KEY_RIGHT # ENTER, SPACE, RIGHT -->
          if cursor[:id] == :config
            #if cursor[:range]
            #  node_input(cursor)
            #else
              toggle_node cursor
            #end
          else
            list_nodes = get_list_nodes(cursor)
            if list_nodes && list_nodes.size > 0
              current = cursor
              nav_stack.push cursor
              navables = list_nodes_to_navable(list_nodes)
              if navables.size > 0
                cursor = navables[0]
              end
            else
              if cursor[:id] == :choice
                node_input(cursor)
              end
            end
          end
        when KEY_UP # UP
          cursor = nav_prev(list_nodes, cursor)
        when KEY_DOWN # DOWN
          cursor = nav_next(list_nodes, cursor)
        when KEY_LEFT, KEY_ESC
          begin
            current = @conf[current[:parent]]
          end while current[:id] == :group
          cursor = nav_stack.pop if nav_stack.size > 0
        when ?q, ?Q
          break
        when ?x, ?X
          export()
        when ?s, ?S
          save_config()
        when ?l, ?L
          if load_config()
            current = top_node()
            list_nodes, cursor = show_list_nodes(current)
            nav_stack = []
          end
        else
          # puts "Unknown command: #{c.chr}, skipped."
          # sleep(0.5)
        end
        list_nodes, cursor = show_list_nodes(current, cursor)
      end
    end        
  end
  
end  
