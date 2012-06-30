# encoding: utf-8
#
  require 'erb'

  class Nav < ::Array
  ##
  #
    def Nav.version()
      '1.3.1'
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

  # for use in a controller
  #
  #   nav_for(:main) do |nav|
  #
  #     nav.link 'Home', root_path
  #
  #   end
  #
    def Nav.for(*args, &block)
      new(*args, &block).tap do |nav|
        nav.strategy = :instance_exec
      end
    end

  # for use in a view
  #
  #   <%= nav_for(:main) %>
  #
    def for(controller)
      @controller = controller
      build!
      compute_active!
      self
    end

  # for use when the controller instance is available *now*
  #
  # Nav.create do |nav|
  #
  #   nav.link 'Home', root_path
  #
  # end
  #
    def Nav.build(*args, &block)
      if defined?(::ActionController::Base)
        controller = args.grep(::ActionController::Base).first
        args.delete(controller)
      end

      new(*args, &block).tap do |nav|
        nav.strategy = :call
        nav.controller = controller || Current.controller || Current.mock_controller
        nav.build!
        nav.compute_active!
      end
    end

  ##
  #
    attr_accessor(:name)
    attr_accessor(:block)
    attr_accessor(:controller)
    attr_accessor(:strategy)

    def initialize(name = :main, &block)
      @name = name.to_s
      @block = block
      @already_computed_active = false
      @controller = nil
      @strategy = :call
    end

    def evaluate(block, *args)
      args = args.slice(0 .. (block.arity < 0 ? -1 : block.arity))
      @strategy == :instance_exec ? @controller.instance_exec(*args, &block) : block.call(*args)
    end

    def build!
      evaluate(@block, nav = self)
    end

    def link(*args, &block)
      nav = self
      link = Link.new(nav, *args, &block)
      push(link)
      link
    end

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

    def request
      @controller.send(:request)
    end

    def fullpath
      request.fullpath
    end

    def path_info
      path_info = fullpath.scan(%r{[^/]+})
    end

    class Template < ::String
      def initialize(template = nil, &block)
        @erb = ERB.new(template || block.call)
        @binding = block.binding
      end

      def render
        result = @erb.result(@binding)
        result.respond_to?(:html_safe) ? result.html_safe : result
      end
    end

    def template
      @template ||= Template.new do
        <<-__
          <nav class="nav-<%= name %>">
            <ul>
              <% each do |link| %>
                <li class="<%= link.active ? :active : :inactive %>">
                  <a href="<%= link.url %>" class="<%= link.active ? :active : :inactive %>"><%= link.content %></a>
                </li>
              <% end %>
            </ul>
          </nav>
        __
      end
    end

    def template=(template)
      @template = Template.new(template.to_s){}
    end

    def to_html
      template.render
    end

    alias_method(:to_s, :to_html)
    alias_method(:to_str, :to_html)
    alias_method(:html_safe, :to_html)
    
    def html_safe?
      true
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

      def initialize(nav, *args, &block)
        @nav = nav

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
      end

      def compute_active!
        @active = @nav.evaluate(@compute_active, link = self)
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

      %w( controller request fullpath path_info ).each do |method|
        class_eval <<-__, __FILE__, __LINE__
          def #{ method }(*args, &block)
            @nav.#{ method }(*args, &block)
          end
        __
      end

      def url
        controller.send(:url_for, @options)
      end
      alias_method(:href, :url)

      def to_s
        content.to_s
      end

      def Link.default_active_pattern_for(content)
        %r/\b#{ content.to_s.strip.downcase.sub(/\s+/, '_') }\b/i
      end

      def Link.default_active_block_for(pattern)
        proc do |link|
          path_info = link.path_info
          depth = -1
          matched = false
          path_info.each{|path| depth += 1; break if(matched = path =~ pattern)}
          weight = matched ? depth : nil
        end
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
