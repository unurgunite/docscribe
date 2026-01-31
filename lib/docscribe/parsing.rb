# frozen_string_literal: true

require 'parser/source/buffer'
require 'rubygems' # for Gem::Version

module Docscribe
  # Parser backend selection for Docscribe.
  #
  # Docscribe always works with a parser-gem-compatible AST (`Parser::AST::Node`) and
  # parser source locations (`Parser::Source::*`) because rewriting relies on
  # `Parser::Source::TreeRewriter`.
  #
  # Ruby 3.4+ introduces new syntax features that can outpace the parser gem.
  # On Ruby >= 3.4, Docscribe parses using Prism and translates Prism's AST into the
  # parser-gem AST via `Prism::Translation`.
  #
  # You can force a backend via the `DOCSCRIBE_PARSER_BACKEND` environment variable:
  # - `parser` (parser gem)
  # - `prism`  (Prism + translation)
  module Parsing
    class << self
      # Parse Ruby source into an AST.
      #
      # @param code [String] Ruby source code
      # @param file [String] virtual filename used for locations/errors
      # @param backend [Symbol] :auto (default), :parser, or :prism
      # @return [Parser::AST::Node, nil] root AST node (nil for empty/whitespace-only source)
      # @raise [ArgumentError] if backend is unknown
      # @raise [Parser::SyntaxError] if parsing fails (backend-dependent error class)
      def parse(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_buffer(buffer, backend: backend)
      end

      # Parse an existing Parser::Source::Buffer into an AST.
      #
      # This is the preferred entry point when the caller will later rewrite the same buffer
      # with `Parser::Source::TreeRewriter`.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param backend [Symbol] :auto (default), :parser, or :prism
      # @return [Parser::AST::Node, nil]
      # @raise [ArgumentError] if backend is unknown
      # @raise [Parser::SyntaxError] if parsing fails (backend-dependent error class)
      def parse_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse(buffer)
      end

      # Parse Ruby source into AST + comments.
      #
      # @param code [String]
      # @param file [String]
      # @param backend [Symbol] :auto (default), :parser, or :prism
      # @return [Array<(Parser::AST::Node, Array<Parser::Source::Comment>)>]
      # @raise [ArgumentError] if backend is unknown
      # @raise [Parser::SyntaxError] if parsing fails (backend-dependent error class)
      def parse_with_comments(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_with_comments_buffer(buffer, backend: backend)
      end

      # Parse AST + comments from an existing buffer.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param backend [Symbol] :auto (default), :parser, or :prism
      # @return [Array<(Parser::AST::Node, Array<Parser::Source::Comment>)>]
      # @raise [ArgumentError] if backend is unknown
      # @raise [Parser::SyntaxError] if parsing fails (backend-dependent error class)
      def parse_with_comments_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse_with_comments(buffer)
      end

      # Select the effective backend (:parser or :prism).
      #
      # Precedence:
      # 1) explicit `backend:` argument
      # 2) `DOCSCRIBE_PARSER_BACKEND` env var
      # 3) auto-selection based on RUBY_VERSION
      #
      # @param backend [Symbol] :auto (default), :parser, or :prism
      # @return [Symbol] :parser or :prism
      # @raise [ArgumentError] if an unknown backend is requested
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

      # Build the underlying parser instance for the selected backend.
      #
      # IMPORTANT: even in Prism mode, this returns a parser-gem-compatible parser object
      # (`Prism::Translation::ParserCurrent`) that produces `Parser::AST::Node`.
      #
      # @param backend [Symbol] :auto, :parser, or :prism
      # @return [Object] responds to `parse` and `parse_with_comments`
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

      # @return [Boolean]
      def ruby_gte_34?
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4')
      end
    end
  end
end
