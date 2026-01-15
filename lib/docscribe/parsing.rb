# frozen_string_literal: true

require 'parser/source/buffer'
require 'rubygems' # for Gem::Version

module Docscribe
  # A module to correctly parse AST according to Ruby version
  module Parsing
    class << self
      def parse(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_buffer(buffer, backend: backend)
      end

      # Parse using an already-created Parser::Source::Buffer.
      # This is important when callers later use Parser::Source::TreeRewriter
      # with the same buffer.
      def parse_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse(buffer)
      end

      def parse_with_comments(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_with_comments_buffer(buffer, backend: backend)
      end

      def parse_with_comments_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse_with_comments(buffer) # => [ast, comments]
      end

      def parser_for(backend: :auto)
        case self.backend(backend)
        when :parser
          require 'parser/current'
          Parser::CurrentRuby.new
        when :prism
          require 'prism'
          Prism::Translation::ParserCurrent.new
        end
      end

      # backend: :auto (default), :parser, :prism
      def backend(backend = :auto)
        env = ENV.fetch('DOCSCRIBE_PARSER_BACKEND', nil)
        backend = env.to_sym if env && !env.empty?

        case backend
        when :auto
          ruby_gte_34? ? :prism : :parser
        when :parser, :prism
          backend
        else
          raise ArgumentError, "Unknown backend: #{backend.inspect}"
        end
      end

      def ruby_gte_34?
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4')
      end
    end
  end
end
