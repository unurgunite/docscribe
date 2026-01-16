# frozen_string_literal: true

require 'parser/source/buffer'
require 'rubygems' # for Gem::Version

module Docscribe
  # Picks the correct Ruby parser backend and returns a `parser`-gem-compatible AST.
  #
  # Docscribe internally works with `parser` AST nodes (e.g. `Parser::AST::Node`) and
  # `Parser::Source::*` location objects so it can use `Parser::Source::TreeRewriter`
  # without reformatting the source.
  #
  # Ruby 3.4+ syntax can outpace the `parser` gem. To keep parsing working on Ruby 3.4+
  # (and Ruby 4.0), Docscribe can parse with Prism and translate Prism’s AST into the
  # `parser` AST via `Prism::Translation`.
  #
  # You can force a backend via the `DOCSCRIBE_PARSER_BACKEND` environment variable
  # (`parser` or `prism`).
  module Parsing
    class << self
      # Parse a Ruby source string into an AST.
      #
      # @param code [String] Ruby source code.
      # @param file [String] A virtual filename used in locations (e.g. for errors and ranges).
      # @param backend [Symbol] :auto (default), :parser, or :prism.
      # @return [Parser::AST::Node, nil] Root node (or nil for empty/whitespace-only source).
      def parse(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_buffer(buffer, backend: backend)
      end

      # Parse using an already-created {Parser::Source::Buffer}.
      #
      # This is important when callers later use {Parser::Source::TreeRewriter} with the
      # same buffer instance (to keep ranges/offsets consistent).
      #
      # @param buffer [Parser::Source::Buffer] Source buffer (must have `.source` set).
      # @param backend [Symbol] :auto (default), :parser, or :prism.
      # @return [Parser::AST::Node, nil] Root node (or nil for empty/whitespace-only source).
      def parse_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse(buffer)
      end

      # Parse a Ruby source string into AST + comments.
      #
      # @param code [String] Ruby source code.
      # @param file [String] A virtual filename used in locations (e.g. for errors and ranges).
      # @param backend [Symbol] :auto (default), :parser, or :prism.
      # @return [Array<(Parser::AST::Node, Array<Parser::Source::Comment>)>]
      #   The AST root node (or nil) and an array of comments.
      def parse_with_comments(code, file: '(docscribe)', backend: :auto)
        buffer = Parser::Source::Buffer.new(file, source: code)
        parse_with_comments_buffer(buffer, backend: backend)
      end

      # Parse AST + comments using an existing {Parser::Source::Buffer}.
      #
      # @param buffer [Parser::Source::Buffer] Source buffer (must have `.source` set).
      # @param backend [Symbol] :auto (default), :parser, or :prism.
      # @return [Array<(Parser::AST::Node, Array<Parser::Source::Comment>)>]
      #   The AST root node (or nil) and an array of comments.
      def parse_with_comments_buffer(buffer, backend: :auto)
        parser = parser_for(backend: backend)
        parser.parse_with_comments(buffer)
      end

      # @api private
      # Build the underlying parser instance for the selected backend.
      #
      # @param backend [Symbol] :auto, :parser, or :prism.
      # @return [Object] An object responding to `parse` and `parse_with_comments`.
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

      # Select the backend (:parser or :prism).
      #
      # @param backend [Symbol] :auto (default), :parser, or :prism.
      # @return [Symbol] :parser or :prism.
      # @raise [ArgumentError] if an unknown backend is requested.
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

      # @api private
      # @return [Boolean] true if running on Ruby 3.4+.
      def ruby_gte_34?
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4')
      end
    end
  end
end
