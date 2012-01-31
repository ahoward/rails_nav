# encoding: utf-8

#
  require 'rails_current'
  require 'rails_helper'
  require 'tagz'

  module Nav
    def Nav.version()
      '0.0.4'
    end

    class Item
      attr_accessor(:label)
      attr_accessor(:options)
      attr_accessor(:html_options)
      attr_accessor(:pattern)
      attr_accessor(:active)

      def initialize(*args, &block)
        options =
          if args.size == 1 and args.last.is_a?(Hash)
            args.extract_options!.to_options!
          else
            {}
          end

        @label = options[:label]               || args.shift || 'Slash'
        @options = options[:options]           || args.shift || '/'
        @html_options = options[:html_options] || args.shift || {}
        @pattern = options[:pattern]           || args.shift || default_active_pattern
        @active = options[:active]             || block      || default_active_block
      end

      def default_active_pattern
        %r/\b#{ label.to_s.strip.downcase.sub(/\s+/, '_') }\b/i
      end

      def default_active_block
        pattern = @pattern
        proc do
          path_info = request.fullpath.scan(%r{[^/]+})
          depth = -1
          matched = false
          path_info.each{|path| depth += 1; break if(matched = path =~ pattern)}
          weight = matched ? depth : nil
        end
      end

      def active?(&block)
        if block
          @active = block
        else
          Current.controller.instance_eval(&@active)
        end
      end
      alias_method('active', 'active?')
      alias_method('activate', 'active?')
    end

    class List < ::Array
      extend Tagz.globally
      include Tagz.globally

      def item(*args, &block)
        push(Nav::Item.new(*args, &block))
      end
      %w( add nav tab ).each{|dst| alias_method(dst, 'item')}

      %w( name label ).each do |attr|
        module_eval <<-__
          def #{ attr }(*args)
            @#{ attr } = args.join(' ') unless args.blank?
            @#{ attr }
          end
          alias_method('#{ attr }=', '#{ attr }')
        __
      end

      def options(opts = {})
        (@options ||= Map.new).tap{|options| options.update(opts)}
      end

      def to_html(*args, &block)
        List.to_html(self, *args, &block)
      end
      alias_method(:to_s, :to_html)

      def List.strategy(*value)
        @strategy ||= (value.first || :dl).to_s
      end

      def List.strategy=(value)
        @strategy = value.first.to_s
      end

      def List.to_html(*args, &block)
        list = args.shift
        options = args.extract_options!.to_options!
        weights = []

        list.each_with_index do |item, index|
          is_active = item.active?
          weights[index] = case is_active
            when nil, false then 0
            when true then 1
            else Integer(is_active)
          end
        end

        active = Array.new(weights.size){ false }
        active[weights.index(weights.max)] = true

        helper = Helper.new

        if list.name
          options[:id] ||= list.name
          options[:class] = [options[:class], list.name].join(' ')
        end

        options.update(list.options)

        list_ = List.strategy =~ /dl/ ? :dl_ : :ul_
        item_ = List.strategy =~ /dl/ ? :dd_ : :li_

        nav_(options){
          unless List.strategy =~ /dl/
            label_{ list.label } unless list.label.blank?
          end

          send(list_){
            first_index = 0
            last_index = list.size - 1

            if List.strategy =~ /dl/
              dt_{ list.label } unless list.label.blank?
            end

            list.each_with_index do |element, index|
              css_id = "nav-#{ index }"
              css_class = active[index] ? 'active' : 'inactive'
              css_class += ' nav'
              css_class += ' first' if index == first_index
              css_class += ' last' if index == last_index

              send(item_, :id => css_id, :class => css_class){
                options = element.html_options || {}
                options[:href] = helper.url_for(element.options)
                options[:class] = active[index] ? 'active' : ''
                a_(options){ element.label }
              }
            end
          }
        }
      end
    end
  end

# factored out mixin for controllers/views
#
  module Nav
    def Nav.extend_action_controller!
      if defined?(::ActionController::Base)
        ::ActionController::Base.module_eval do
          class << self
            def nav(*args, &block)
              options = args.extract_options!.to_options!
              name = args.first || options[:name] || :main
              nav_name = [:nav, name].join('_')
              args.push(options)

              define_method(nav_name) do
                nav_list = Nav::List.new
                instance_exec(nav_list, &block)
                nav_list.name = name
                nav_list
              end

              protected(nav_name)
            end
            alias_method(:nav_for, :nav)
          end

          helper do
            def nav(*args, &block)
              options = args.extract_options!.to_options!
              name = args.first || options[:name] || :main
              nav_name = [:nav, name].join('_')
              args.push(options)

              if controller.respond_to?(nav_name)
                nav = controller.send(nav_name)
                nav.to_html(*args, &block)
              end
            end
            alias_method(:nav_for, :nav)
          end
        end
      end
    end
  end

  if defined?(Rails::Engine)
    class Engine < Rails::Engine
      config.before_initialize do
        ActiveSupport.on_load(:action_controller) do
          Nav.extend_action_controller!
        end
      end
    end
  else
    Nav.extend_action_controller!
  end

  Rails_nav = Nav
