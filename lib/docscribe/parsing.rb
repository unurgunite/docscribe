# frozen_string_literal: true

require 'parser/source/buffer'
require 'rubygems' # for Gem::Version

module Docscribe
  # Parser backend selection for Docscribe.
  #
  # Docscribe always works with parser-gem-compatible AST nodes (`Parser::AST::Node`)
  # and parser source locations (`Parser::Source::*`) because rewriting relies on
  # `Parser::Source::TreeRewriter`.
  #
  # On Ruby 3.4+, Prism can parse newer syntax before the parser gem fully supports it,
  # so Docscribe can use Prism and translate the result into parser-gem-compatible nodes.
  #
  # Backends:
  # - `:parser` => parser gem
  # - `:prism`  => Prism + translation
  # - `:auto`   => choose based on runtime Ruby version or env override
  #
  # You can force a backend with:
  # - `DOCSCRIBE_PARSER_BACKEND=parser`
  # - `DOCSCRIBE_PARSER_BACKEND=prism`
  module Parsing
    class << self
      # Parse source code into a parser-gem-compatible AST.
      #
      # @param [String] code Ruby source
      # @param [String] file source name used for parser locations
      # @param [Symbol] backend :auto, :parser, or :prism
      # @return [Parser::AST::Node, nil]
      def parse(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_buffer(buffer, backend: backend)
      end

      # Parse a prepared source buffer into a parser-gem-compatible AST.
      #
      # @param [Parser::Source::Buffer] buffer
      # @param [Symbol] backend :auto, :parser, or :prism
      # @return [Parser::AST::Node, nil]
      def parse_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse(buffer)
      end

      # Parse source code and also return comments when supported by the backend.
      #
      # @param [String] code Ruby source
      # @param [String] file source name used for parser locations
      # @param [Symbol] backend :auto, :parser, or :prism
      # @return [Array<(Parser::AST::Node, Array)>]
      def parse_with_comments(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_with_comments_buffer(buffer, backend: backend)
      end

      # Parse a prepared source buffer and also return comments when supported by the backend.
      #
      # @param [Parser::Source::Buffer] buffer
      # @param [Symbol] backend :auto, :parser, or :prism
      # @return [Array<(Parser::AST::Node, Array)>]
      def parse_with_comments_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse_with_comments(buffer)
      end

      # Resolve the effective parser backend.
      #
      # Resolution order:
      # - `DOCSCRIBE_PARSER_BACKEND` env var, if set
      # - explicit `backend:` argument
      # - auto choice based on Ruby version
      #
      # @param [Symbol] backend requested backend
      # @raise [ArgumentError]
      # @return [Symbol] :parser or :prism
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

      private

      # Build the backend-specific parser object.
      #
      # @private
      # @param [Symbol] backend
      # @return [Object]
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

      # Whether the current Ruby version is 3.4 or newer.
      #
      # @private
      # @return [Boolean]
      def ruby_gte_34?
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4')
      end
    end
  end
end
