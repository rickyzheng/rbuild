# frozen_string_literal: true

#
# RBuild: a Linux KBuild like configure/build system by Ruby DSL.
#
# Copy right(C) 2008, Ricky Zheng <ricky_gz_zheng@yahoo.co.nz>
#
# Licence: GNU GPLv2
#
# http://rbuild.sourceforge.net/
#

$debug_in_rb = false

module RBuild
  module Menuconfig
    private

    if RUBY_VERSION >= '1.9.0'
      KEY_SPACE = 32.chr
      KEY_ESC = 27.chr
      if RUBY_PLATFORM =~ /(win32|win64|mingw|mswin|windows)/
        KEY_RIGHT = 77.chr
        KEY_LEFT = 75.chr
        KEY_UP = 72.chr
        KEY_DOWN = 80.chr
      else
        KEY_RIGHT = 'C'.chr
        KEY_LEFT = 'D'.chr
        KEY_UP = 'A'.chr
        KEY_DOWN = 'B'.chr
      end
    else
      KEY_SPACE = 32
      KEY_ESC = 27
      if RUBY_PLATFORM =~ /(win32|win64|mingw|mswin|windows)/
        KEY_RIGHT = 77
        KEY_LEFT = 75
        KEY_UP = 72
        KEY_DOWN = 80
      else
        KEY_RIGHT = 'C'
        KEY_LEFT = 'D'
        KEY_UP = 'A'
        KEY_DOWN = 'B'
      end
    end

    # conver the viewable nodes list to navable nodes list
    def list_nodes_to_navable(list)
      navable = []
      list.each do |x|
        navable << x[:node] unless x[:node][:id] == :group
      end
      navable
    end

    def nav_prev(list, cur)
      navable = list_nodes_to_navable(list)
      idx = navable.index(cur)
      return cur unless idx
      return cur if idx == 0

      navable[idx - 1]
    end

    def nav_next(list, cur)
      navable = list_nodes_to_navable(list)
      idx = navable.index(cur)
      return cur unless idx
      return cur if idx == navable.size - 1

      navable[idx + 1]
    end

    def clear_screen
      if windows?
        system('cls')
      else
        system('clear')
      end
    end

    # showing the given viewable nodes list.
    def show_list_nodes(current, cursor = nil)
      lists = get_list_nodes(current)
      navables = list_nodes_to_navable(lists)
      cursor ||= (navables[0] || current)

      clear_screen
      puts "=== #{current[:title]} ==="
      puts ''
      lists.each do |list|
        node = list[:node]
        level = list[:level]
        next if node[:title].to_s.empty?

        s = ''
        case node[:id]
        when :group
          s = '  ' + ('-' * level) + " #{node[:title]} " + ('-' * level)
        when :menu
          s = (cursor == node ? '>' : ' ').to_s + (' ' * level) + '-+-' + " #{node[:title]}" + ' -+-'
        when :config
          s = (cursor == node ? '>' : ' ').to_s + (' ' * level) + "[#{node[:hit] ? '*' : ' '}]" + " #{node[:title]}"
        when :choice
          s = (cursor == node ? '>' : ' ').to_s + (' ' * level) + "\{#{node[:hit] ? '*' : ' '}\}" + " #{node[:title]}"
          if node[:hit]
            if !node[:children].empty?
              s += " <#{@conf[node[:value]][:title]}>"
            else
              v = node[:value]
              s += if node[:hex]
                     (' < 0x' + ('%X' % v) + ' >')
                   else
                     " < #{v} >"
                   end
            end
          end
        end
        puts ' ' + s
      end
      puts ''
      show_footer_bar
      [lists, cursor]
    end

    def show_footer_bar
      puts '[[ ' + footer_msg + ' ]]' if footer_msg
      puts '------------------------------'
      puts "  (S)ave   (L)oad   (Q)uit\n"
    end

    # read key press without echo ...
    def getch
      return STDIN.getc if $debug_in_rb

      if windows?
        require 'Win32API'
        fun = Win32API.new('crtdll', '_getch', [], 'L')
        c = fun.call
        if RUBY_VERSION >= '1.9.0'
          c.chr
        else
          c
        end
      else
        require 'io/console'
        require 'io/wait'
        begin
          s = ''
          STDIN.raw do |io|
            sleep 0.1 until io.ready?
            s = io.read_nonblock(3)
          end
        rescue Errno::EINTR
        rescue Errno::EAGAIN
        rescue EOFError
        end
        s[s.size - 1]
      end
    end

    # node value simple input, if range == nil, means string input.
    def simple_input(node, range = nil)
      clear_screen
      puts "=== #{node[:title]} ==="
      puts ''
      puts '  tips: hit ENTER only to keep old value'
      puts '        input ``` reset to empty'
      puts ''

      if range
        while true
          print "Input < #{range.min}..#{range.max} >: "
          s = STDIN.gets.chomp
          if s == '```'
            set_node_no(node)
            break
          elsif s == ''
            break # using current value
          else
            if range.min.is_a?(Integer)
              if node[:hex]
                if s =~ /^0[xX][0-9a-fA-F]+$/
                  value = s.hex
                else
                  puts 'Invalid input, please input HEX format, start with 0x...'
                  redo
                end
              else
                if s =~ /^[0-9]+$/
                  value = s.to_i
                else
                  puts 'Invalid input, only 0-9 digis allowed, press any key try again ...'
                  redo
                end
              end
            else
              value = s
            end
            if range.include?(value)
              set_node_value(node, value)
              break
            else
              puts 'Input no in the range, press any key try again ...'
              getch
            end
          end
        end

      else # no :range provided.

        loop do
          puts "Current value: #{node[:value]}" if node[:value] && node[:value].to_s != ''
          print 'Input: '
          s = STDIN.gets.chomp.strip
          if s == '```'
            set_node_no(node)
            break
          elsif s == ''
            break # using the default value
          else
            if node[:hex]
              if s =~ /^0[xX][0-9a-fA-F]+$/
                value = s.hex
              else
                puts 'Invalid input, please input HEX format number, start with 0x... '
                getch
                redo
              end
            elsif node[:digi]
              if s =~ /^[0-9]+$/
                value = s.to_i
              else
                puts 'Invalid input, please input numbers.'
                getch
                redo
              end
            else
              value = s
            end
            set_node_value(node, value)
          end
          break
        end
      end
    end

    # node value input by choice one of the value from range (could be array or hash)
    def choice_input(node, range)
      values = []
      if range.is_a?(Array)
        if range[0].is_a?(Hash)
          range.each { |v| values << { value: v.keys[0], desc: v[v.keys[0]] } }
        else
          range.each { |v| values << { value: v, desc: v.to_s } }
        end
      elsif range.is_a?(Hash)
        range.each { |v, desc| values << { value: v, desc: desc } }
      end
      do_choice_input(node, values) unless values.empty?
    end

    # values is an array of Hash{:value =>?, :selected =>?, :desc => ?}
    def do_choice_input(node, values)
      cursor = 0
      selected = nil
      values.each_index do |idx|
        elm = values[idx]
        next unless get_node_value(node) == elm[:value]

        elm[:selected] = true
        selected = idx
        cursor = idx
      end

      show_choice_input(node, values, cursor)
      loop do
        c = getch
        case c
        when "\r", KEY_SPACE, KEY_RIGHT # ENTER, SPACE, RIGHT -->
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
        when KEY_UP # UP
          cursor -= 1 if cursor > 0
        when KEY_DOWN # DOWN
          cursor += 1 if cursor < values.size - 1
        when KEY_LEFT, KEY_ESC
          set_node_value(node, values[selected][:value]) if selected
          break
        end
        show_choice_input(node, values, cursor)
      end
    end

    # values is an array of Hash{:value =>?, :selected =>?, :desc => ?}
    def show_choice_input(node, values, cursor)
      clear_screen
      puts "=== #{node[:title]} ==="
      puts ''
      values.each_index do |idx|
        elm = values[idx]
        puts "#{cursor == idx ? '>' : ' '} [#{elm[:selected] ? '*' : ' '}] #{elm[:desc]}"
      end
      puts ''
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
    def menuconfig
      if have_error?
        puts '--- Error ---'
        puts @errmsg.to_s
        return
      end

      current = top_node
      # STDIN.getc
      list_nodes, cursor = show_list_nodes(current)
      nav_stack = []

      loop do
        c = getch
        footer_clear
        case c
        when "\r", KEY_SPACE, KEY_RIGHT # ENTER, SPACE, RIGHT -->
          if cursor[:id] == :config
            toggle_node cursor
          else
            list_nodes = get_list_nodes(cursor)
            if list_nodes && !list_nodes.empty?
              current = cursor
              nav_stack.push cursor
              navables = list_nodes_to_navable(list_nodes)
              cursor = navables[0] unless navables.empty?
            else
              node_input(cursor) if cursor[:id] == :choice
            end
          end
        when KEY_UP # UP
          cursor = nav_prev(list_nodes, cursor)
        when KEY_DOWN # DOWN
          cursor = nav_next(list_nodes, cursor)
        when KEY_LEFT, KEY_ESC
          begin
            current = @conf[current[:parent]]
          end while current[:id] != :menu # always browser from a menu !
          cursor = nav_stack.pop unless nav_stack.empty?
        when 'q', 'Q'
          export
          break
        when 's', 'S'
          save_config
        when 'l', 'L'
          cfg_file_node = @conf[:RBUILD_SYS_CONFIG_LOAD_FILE]
          config_file ||= get_node_value(cfg_file_node).to_s if cfg_file_node
          if merge!(config_file)
            current = top_node
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
