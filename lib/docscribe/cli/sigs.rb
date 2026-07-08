# frozen_string_literal: true

require 'optparse'
require 'docscribe/parsing'
require 'docscribe/types/rbs/provider'

module Docscribe
  module CLI
    # Check RBS signature coverage for Ruby source files.
    #
    # Usage:
    #   docscribe sigs [options] [files...]
    #
    # Parses Ruby source files, extracts method definitions, and checks
    # each method against the configured RBS signature directories.
    # Reports methods that lack RBS type signatures.
    module Sigs
      BANNER = <<~TEXT
        Usage: docscribe sigs [options] [files...]

        Check RBS signature coverage for Ruby source files.

      TEXT

      EXIT_CODES = "\nExit codes:\n    " \
                   "0 - all methods have signatures\n    " \
                   "1 - some methods lack signatures\n    " \
                   '2 - error occurred'

      # @!attribute [rw] name
      #   @return [Symbol]
      #   @param [Symbol] value
      #
      # @!attribute [rw] scope
      #   @return [Symbol]
      #   @param [Symbol] value
      #
      # @!attribute [rw] container
      #   @return [String?]
      #   @param [String?] value
      #
      # @!attribute [rw] file
      #   @return [String]
      #   @param [String] value
      #
      # @!attribute [rw] line
      #   @return [Integer]
      #   @param [Integer] value
      MethodDef = Struct.new(:name, :scope, :container, :file, :line, keyword_init: true)

      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          warn_ruby_version
          options = parse_options(argv)
          paths = expand_paths(argv)
          return no_files_found if paths.empty?

          run_with(options, extract_methods(paths))
        end

        private

        # @private
        # @return [void]
        def warn_ruby_version
          return unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0')

          warn 'Warning: docscribe sigs requires Ruby 3.0+ for RBS support. ' \
               "You are running Ruby #{RUBY_VERSION}."
        end

        # @private
        # @param [Array<String>] argv
        # @return [Hash<Symbol, Object>]
        def parse_options(argv)
          options = { sig_dirs: ['sig'], rbs_collection: false, verbose: false }

          parser = OptionParser.new do |opts|
            opts.banner = BANNER
            register_sig_options(opts, options)
          end

          parser.parse!(argv)
          options
        end

        # @private
        # @param [OptionParser] opts
        # @param [Hash<Symbol, Object>] options
        # @return [void]
        def register_sig_options(opts, options)
          opts.on('-s', '--sig-dir DIR', 'Add RBS signature directory (repeatable)') { |d| options[:sig_dirs] << d }
          opts.on('--rbs-collection', 'Use RBS collection') { options[:rbs_collection] = true }
          opts.on('--verbose', 'Print methods that have signatures too') { options[:verbose] = true }
          opts.on('-h', '--help', 'Show this help') do
            puts opts, EXIT_CODES
            exit 0
          end
        end

        # @private
        # @param [Array<String>] args
        # @return [Array<String>]
        def expand_paths(args)
          files = [] #: Array[String]
          args = ['.'] if args.empty?
          args.each { |path| expand_single_path(files, path) }
          files.uniq.sort
        end

        # @private
        # @param [Array<String>] files
        # @param [String] path
        # @return [void]
        def expand_single_path(files, path)
          if File.directory?(path)
            files.concat(Dir.glob(File.join(path, '**', '*.rb')))
          elsif File.file?(path)
            files << path
          else
            warn "Skipping missing path: #{path}"
          end
        end

        # @private
        # @return [Integer]
        def no_files_found
          warn 'No files found. Pass files or directories (e.g. `docscribe sigs lib`).'
          2
        end

        # @private
        # @param [Hash<Symbol, Object>] options
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @return [Integer]
        def run_with(options, methods)
          return 0 if methods.empty?

          provider = build_provider(options)
          return 2 unless provider

          missing = check_sigs(methods, provider, verbose: options[:verbose])
          report_results(methods, missing)
          missing.empty? ? 0 : 1
        end

        # @private
        # @param [Array<String>] paths
        # @return [Array<Docscribe::CLI::Sigs::MethodDef>]
        def extract_methods(paths)
          methods = [] #: Array[MethodDef]
          paths.each { |path| extract_methods_from_file(path, methods) }
          methods
        end

        # @private
        # @param [String] path
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @raise [Parser::SyntaxError]
        # @raise [StandardError]
        # @return [void]
        # @return [nil] if Parser::SyntaxError
        # @return [nil] if StandardError
        def extract_methods_from_file(path, methods)
          src = File.read(path)
          ast = Docscribe::Parsing.parse(src, file: path)
          return unless ast

          walk_for_methods(ast, [], methods, path)
        rescue Parser::SyntaxError => e # steep:ignore
          warn "Syntax error in #{path}: #{e.message}"
        rescue StandardError => e
          warn "Error parsing #{path}: #{e.class}: #{e.message}"
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @param [Boolean] inside_sclass
        # @return [void]
        def walk_for_methods(node, containers, methods, path, inside_sclass: false)
          return unless node.is_a?(Parser::AST::Node)

          case node.type
          when :class, :module then walk_class_module(node, containers, methods, path)
          when :sclass then walk_sclass(node, containers, methods, path)
          when :def then collect_def(node, containers, methods, path, inside_sclass: inside_sclass)
          when :defs then collect_defs(node, containers, methods, path)
          else walk_children(node, containers, methods, path, inside_sclass: inside_sclass)
          end
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @return [void]
        def walk_class_module(node, containers, methods, path)
          containers.push(const_name(node.children[0]))
          node.children.drop(1).each { |c| walk_for_methods(c, containers, methods, path) }
          containers.pop
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @return [void]
        def walk_sclass(node, containers, methods, path)
          node.children.drop(1).each { |c| walk_for_methods(c, containers, methods, path, inside_sclass: true) }
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @param [Boolean] inside_sclass
        # @return [void]
        def walk_children(node, containers, methods, path, inside_sclass: false)
          node.children.each { |c| walk_for_methods(c, containers, methods, path, inside_sclass: inside_sclass) }
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @param [Boolean] inside_sclass
        # @return [void]
        def collect_def(node, containers, methods, path, inside_sclass: false)
          methods << MethodDef.new(
            name: node.children[0],
            scope: inside_sclass ? :class : :instance,
            container: container_name(containers),
            file: path,
            line: node.loc&.line || 1
          )
        end

        # @private
        # @param [Parser::AST::Node] node
        # @param [Array<String>] containers
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [String] path
        # @return [void]
        def collect_defs(node, containers, methods, path)
          methods << MethodDef.new(
            name: node.children[1],
            scope: :class,
            container: container_name(containers),
            file: path,
            line: node.loc&.line || 1
          )
        end

        # @private
        # @param [Array<String>] containers
        # @return [String?]
        def container_name(containers)
          containers.empty? ? nil : containers.join('::')
        end

        # @private
        # @param [Parser::AST::Node] node
        # @return [String]
        def const_name(node)
          return node.to_s unless node.is_a?(Parser::AST::Node)
          return node.children[1].to_s if node.type == :const

          node.children.map { |c| c.is_a?(Parser::AST::Node) ? const_name(c) : c.to_s }.join('::')
        end

        # @private
        # @param [Hash<Symbol, Object>] options
        # @raise [LoadError]
        # @raise [StandardError]
        # @return [Docscribe::Types::RBS::Provider?]
        # @return [nil] if LoadError
        # @return [nil] if StandardError
        def build_provider(options)
          dirs = options[:rbs_collection] ? load_collection_dirs : [] #: Array[String]
          Docscribe::Types::RBS::Provider.new(sig_dirs: options[:sig_dirs], collection_dirs: dirs)
        rescue LoadError
          warn 'Docscribe: rbs gem is not installed. Add `gem "rbs"` to your Gemfile ' \
               'or run `bundle exec rbs collection install`.'
          nil
        rescue StandardError => e
          warn "Docscribe: Failed to initialize RBS provider: #{e.class}: #{e.message}"
          nil
        end

        # @private
        # @raise [StandardError]
        # @return [Array<String>]
        # @return [Array] if StandardError
        def load_collection_dirs
          dir = Docscribe::Types::RBS::CollectionLoader.resolve
          dir ? [dir] : []
        rescue StandardError => e
          warn "Docscribe: Failed to load RBS collection: #{e.class}: #{e.message}"
          []
        end

        # @private
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [Docscribe::Types::RBS::Provider] provider
        # @param [Boolean] verbose
        # @return [Array<Docscribe::CLI::Sigs::MethodDef>]
        def check_sigs(methods, provider, verbose:)
          missing = [] #: Array[MethodDef]
          methods.each do |m|
            sig = lookup_signature(m, provider)
            puts "  OK  #{format_method(m)} (#{m.file}:#{m.line})" if sig && verbose
            puts "  MISS #{format_method(m)} (#{m.file}:#{m.line})" unless sig
            missing << m unless sig
          end
          missing
        end

        # @private
        # @param [Docscribe::CLI::Sigs::MethodDef] method_def
        # @param [Docscribe::Types::RBS::Provider] provider
        # @return [Object, nil]
        def lookup_signature(method_def, provider)
          container = method_def.container
          return nil unless container

          provider.signature_for(
            container: container,
            scope: method_def.scope,
            name: method_def.name
          )
        end

        # @private
        # @param [Docscribe::CLI::Sigs::MethodDef] method_def
        # @return [String]
        def format_method(method_def)
          prefix = method_def.scope == :class ? 'self.' : ''
          container = method_def.container ? "#{method_def.container}#" : ''
          "#{container}#{prefix}#{method_def.name}"
        end

        # @private
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] methods
        # @param [Array<Docscribe::CLI::Sigs::MethodDef>] missing
        # @return [void]
        def report_results(methods, missing)
          puts
          if missing.empty?
            puts "Docscribe: All #{methods.size} methods have RBS signatures"
          else
            puts "Docscribe: #{missing.size}/#{methods.size} methods missing RBS signatures"
          end
        end
      end
    end
  end
end
