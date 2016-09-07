# encoding: utf-8
#
  require 'erb'
  require 'map'

  class Nav < ::Array
  ##
  #
    def Nav.version()
      '2.8.0'
    end

    def Nav.dependencies
      {
        'rails_current' => [ 'rails_current' , ' >= 1.6'   ],
        'rails_helper'  => [ 'rails_helper'  , ' >= 1.2'   ],
        'map'           => [ 'map'           , ' >= 6.5'   ],
      }
    end

    def Nav.description
      'declarative navigation for rails applications'
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
  # Nav.build do |nav|
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
    attr_accessor(:weights)
    attr_accessor(:active)

    def initialize(name = :main, &block)
      @name = name.to_s
      @block = block
      @already_computed_active = false
      @controller = nil
      @strategy = :call
      @active = nil
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
      nav = self

      unless empty?
        weights = []

        each_with_index do |link, index|
          link.controller = @controller
          active = link.compute_active!

          weight =
            begin
              case active
                when nil, false
                  -1
                when true
                  0
                else
                  Integer(active)
              end
            rescue
              -1
            end

          link.weight = weight
          weights[index] = weight
        end

        nav.weights = weights

        each_with_index do |link, index|
          link.active = false
        end

        more_than_one_link =
          size > 1

        equivalently_active =
          weights.uniq.size < 2

        no_clear_winner =
          more_than_one_link && equivalently_active

        active_link =
          if no_clear_winner
            detect{|link| link.default}
          else
            max = weights.max
            longest_matching_link = select{|link| link.weight == max}.sort{|a,b| a.content.size <=> b.content.size}.last
          end

        if active_link
          active_link.active = true
          nav.active = active_link
        end

        @already_computed_active = true
      end

      nav
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
      attr_accessor(:args)
      attr_accessor(:options)
      attr_accessor(:controller)
      attr_accessor(:content)
      attr_accessor(:options)
      attr_accessor(:pattern)
      attr_accessor(:compute_active)
      attr_accessor(:active)
      attr_accessor(:default)
      attr_accessor(:weight)
      attr_accessor(:slug)
      attr_accessor(:config)

      def initialize(*args, &block)
      #
        @options =
          if args.last.is_a?(Hash)
            args.extract_options!.to_options!
          else
            {}
          end
      #
        args.each{|arg| @nav = arg if arg.is_a?(Nav)}
        args.delete_if{|arg| arg.is_a?(Nav)}

        unless @nav
          @nav = Nav.new
          @nav.controller = Current.mock_controller
        end

      #
        @content        = getopt!(:content){ args.shift || 'Slash' }
        @url            = getopt!(:url){ args.shift || {} }
        @pattern        = getopt!(:pattern){ args.shift || Link.default_active_pattern_for(@content) }
        @compute_active = getopt!(:active){ block || Link.default_active_block_for(@pattern) }
        @default        = getopt!(:default){ nil }

      #
        @slug = Slug.for(@content, :join => '-')
        @already_computed_active = nil

        @config = Map.new
      end

      def getopt!(key, &block)
        @options.has_key?(key) ? @options.delete(key) : (block && block.call)
      end

      def compute_active!
        @active = 
          if @compute_active.respond_to?(:call)
            @nav.evaluate(@compute_active, link = self)
          else
            !!@compute_active
          end
      ensure
        @already_computed_active = true
      end

      def compute_active
        compute_active! unless @already_computed_active
      end

      def default?
        !!@default
      end

      %w( controller request fullpath path_info ).each do |method|
        class_eval <<-__, __FILE__, __LINE__
          def #{ method }(*args, &block)
            @nav.#{ method }(*args, &block)
          end
        __
      end

      def url
        controller.send(:url_for, *@url)
      end
      alias_method(:href, :url)

      def to_s
        content.to_s
      end

      def inspect
        super
      end

      def Link.default_active_pattern_for(content)
        path_info = Slug.for(content.to_s.split('/').first, :join => '[_-]*')
        %r/\b#{ path_info }\b/i
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

    class Slug < ::String
      Join = '-'

      def Slug.for(*args)
        options = args.last.is_a?(Hash) ? args.pop : {}
        join = (options[:join]||options['join']||Join).to_s
        string = args.flatten.compact.join(join)
        string = unidecode(string).titleize
        words = string.to_s.scan(%r/\w+/)
        words.map!{|word| word.gsub %r/[^0-9a-zA-Z_-]/, ''}
        words.delete_if{|word| word.nil? or word.strip.empty?}
        new(words.join(join).downcase)
      end

      begin
        require 'stringex'
      rescue LoadError
      end

      unless defined?(Stringex::Unidecoder)
        def Slug.unidecode(string)
          string
        end
      else
        def Slug.unidecode(string)
          Stringex::Unidecoder.decode(string)
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

        def nav_for(*args, &block)
          options = args.extract_options!.to_options!
          name = args.first || options[:name] || :main
          Nav.for(name, &block).for(controller = self)
        end
        alias_method(:nav, :nav_for)

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
