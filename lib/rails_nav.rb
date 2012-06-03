# encoding: utf-8
#
  class Nav < ::Array
  ##
  #
    def Nav.version()
      '1.1.1'
    end

    def Nav.dependencies
      {
        'rails_current' => [ 'rails_current' , ' >= 1.6'   ],
        'rails_helper'  => [ 'rails_helper' , ' >= 1.2'   ]
      }
    end

    begin
      require 'rubygems'
    rescue LoadError
      nil
    end

    Nav.dependencies.each do |lib, dependency|
      gem(*dependency) if defined?(gem)
      require(lib)
    end

  ##
  #
    def Nav.for(*args, &block)
      new(*args, &block)
    end

    def for(controller)
      @controller = controller
      build!
      compute_active!
      self
    end

  ##
  #
    attr_accessor(:name)
    attr_accessor(:block)
    attr_accessor(:controller)

    def initialize(name = 'nav', &block)
      @name = name.to_s
      @block = block
      @already_computed_active = false
      @controller = nil
    end

    def build!
      @controller.instance_exec(self, &@block)
      self
    end

    def link(*args, &block)
      nav = self
      link = Link.new(nav, *args, &block)
      push(link)
      link
    end

  ##
  #
    def compute_active!
      unless empty?
        weights = []

        each_with_index do |link, index|
          link.controller = @controller
          active = link.compute_active!

          weights[index] =
            case active
              when nil, false
                -1
              when true
                0
              else
                Integer(active)
            end
        end

        each_with_index do |link, index|
          link.active = false
        end

        active_link = self[weights.index(weights.max)]

        active_link.active = true

        @already_computed_active = true
      end

      self
    end

    def compute_active
      compute_active! unless @already_computed_active
      self
    end

  ##
  #
    class Link
      attr_accessor(:nav)
      attr_accessor(:controller)
      attr_accessor(:content)
      attr_accessor(:options)
      attr_accessor(:pattern)
      attr_accessor(:active)
      attr_accessor(:compute_active)

      def initialize(*args, &block)
        @nav = args.grep(Nav).first and args.delete(@nav)

        options =
          if args.size == 1 and args.last.is_a?(Hash)
            args.extract_options!.to_options!
          else
            {}
          end

        @content        = options[:content]      || args.shift || 'Slash'
        @options        = options[:options]      || args.shift || {}
        @pattern        = options[:pattern]      || args.shift || Link.default_active_pattern_for(@content)
        @compute_active = options[:active]       || block      || Link.default_active_block_for(@pattern)

        @already_computed_active = nil
        @active = nil
        @controller = nil
      end

      def to_s
        content.to_s
      end

      def url
        @controller.send(:url_for, @options)
      end
      alias_method(:href, :url)

      def Link.default_active_pattern_for(content)
        %r/\b#{ content.to_s.strip.downcase.sub(/\s+/, '_') }\b/i
      end

      def Link.default_active_block_for(pattern)
        proc do |*args|
          path_info = request.fullpath.scan(%r{[^/]+})
          depth = -1
          matched = false
          path_info.each{|path| depth += 1; break if(matched = path =~ pattern)}
          weight = matched ? depth : nil
        end
      end

      def compute_active!
        block = @compute_active
        args = [self].slice(0 .. (block.arity < 0 ? -1 : block.arity))
        @active = @controller.send(:instance_exec, *args, &block)
      ensure
        @already_computed_active = true
      end

      def compute_active
        compute_active! unless @already_computed_active
        @active
      end

      def active?
        !!@active
      end
    end
  end

# factored out mixin for controllers/views
#
  def Nav.extend_action_controller!
    if defined?(::ActionController::Base)
      ::ActionController::Base.module_eval do
        class << self
          def nav_for(*args, &block)
            options = args.extract_options!.to_options!
            name = args.first || options[:name] || :main
            which_nav = [:nav, name].join('_')

            define_method(which_nav){ Nav.for(name, &block) }

            protected(which_nav)
          end
          alias_method(:nav, :nav_for)
        end

        helper do
          def nav_for(*args, &block)
            options = args.extract_options!.to_options!
            name = args.first || options[:name] || :main
            which_nav = [:nav, name].join('_')
            nav = controller.send(which_nav).for(controller)
          end
          alias_method(:nav, :nav_for)
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
  Nav
