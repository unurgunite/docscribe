# frozen_string_literal: true

require 'optparse'

module Docscribe
  module CLI
    # Generator for TagPlugin and CollectorPlugin boilerplate.
    #
    # Usage:
    #   docscribe generate tag MyPlugin
    #   docscribe generate collector MyPlugin
    #   docscribe generate tag MyPlugin --output lib/docscribe_plugins
    #   docscribe generate tag MyPlugin --stdout
    module Generate
      PLUGIN_TYPES = %w[tag collector].freeze

      NEXT_STEPS_TEMPLATE = <<~TEXT
        Next steps:
          1. Open %<path>s and implement the plugin logic.
             %<hint>s

        2. Register the plugin in your docscribe_plugins.rb:

               require_relative '%<require_path>s'
               Docscribe::Plugin::Registry.register(%<base_name>s.new)

        3. Add the file to docscribe.yml:

               plugins:
                 require:
                   - ./docscribe_plugins
      TEXT

      class << self
        # Run the `generate` subcommand.
        #
        # @param [Array<String>] argv
        # @raise [OptionParser::InvalidOption]
        # @return [Integer] exit code
        def run(argv)
          opts, parser = parse_generate_options(argv)
          return 0 if opts[:help]

          plugin_type, class_name = extract_generate_args(argv)
          result = validate_generate_args(plugin_type, class_name, parser)
          return result if result

          content = render(plugin_type, class_name)
          dispatch_output(content, plugin_type, class_name, opts)
        end

        private

        # Parse options for the generate subcommand.
        #
        # @private
        # @param [Array<String>] argv
        # @raise [OptionParser::InvalidOption]
        # @return [Array(Hash, OptionParser)]
        def parse_generate_options(argv)
          opts = { output: nil, stdout: false, help: false }
          parser = build_option_parser(opts)

          begin
            parser.parse!(argv)
          rescue OptionParser::InvalidOption => e
            warn e.message
            warn parser
          end

          [opts, parser]
        end

        # Extract plugin_type and class_name from remaining argv.
        #
        # @private
        # @param [Array<String>] argv
        # @return [Array(String, String)]
        def extract_generate_args(argv)
          [argv.shift, argv.shift]
        end

        # Validate generate arguments and return exit code on failure.
        #
        # @private
        # @param [String, nil] plugin_type
        # @param [String, nil] class_name
        # @param [OptionParser] parser
        # @return [Integer, nil] exit code or nil if valid
        def validate_generate_args(plugin_type, class_name, parser)
          return 1 unless args_provided?(plugin_type, class_name, parser)
          return 1 unless known_type?(plugin_type)
          return 1 unless valid_name?(class_name)

          nil
        end

        # Render plugin boilerplate for the given type and class name.
        #
        # @private
        # @param [String] plugin_type 'tag' or 'collector'
        # @param [String] class_name  CamelCase plugin class name
        # @return [String]
        def render(plugin_type, class_name)
          case plugin_type
          when 'tag'       then tag_template(class_name)
          when 'collector' then collector_template(class_name)
          end
        end

        # Template for a TagPlugin.
        #
        # @private
        # @param [String] class_name
        # @return [String]
        def tag_template(class_name)
          <<~RUBY
            # frozen_string_literal: true

            require 'docscribe/plugin'

            # #{class_name} — a Docscribe TagPlugin.
            #
            # TagPlugins hook into already-collected method insertions and append
            # additional YARD tags to the generated doc block.
            #
            # The +#call+ method is invoked once per documented method. Return an
            # empty array if this plugin has nothing to add for a particular method.
            #
            # @example Registration
            #   Docscribe::Plugin::Registry.register(#{class_name}.new)
            class #{class_name} < Docscribe::Plugin::Base::TagPlugin
              # Generate additional YARD tags for a documented method.
              #
              # Available context attributes:
              #   context.node            # Parser::AST::Node — the :def or :defs node
              #   context.container       # String  — e.g. "MyModule::MyClass"
              #   context.scope           # Symbol  — :instance or :class
              #   context.visibility      # Symbol  — :public, :protected, or :private
              #   context.method_name     # Symbol  — method name
              #   context.inferred_params # Hash    — { "name" => "InferredType" }
              #   context.inferred_return # String  — inferred return type
              #   context.source          # String  — raw method source text
              #
              # @param [Docscribe::Plugin::Context] context method context snapshot
              # @return [Array<Docscribe::Plugin::Tag>]
              def call(context)
                # TODO: implement plugin logic
                #
                # Examples:
                #
                #   Simple text tag:
                #     Docscribe::Plugin::Tag.new(name: 'since', text: '1.0.0')
                #     # => # @since 1.0.0
                #
                #   Tag with types:
                #     Docscribe::Plugin::Tag.new(name: 'raise', types: ['ArgumentError'], text: 'if invalid')
                #     # => # @raise [ArgumentError] if invalid
                #
                #   Conditional tag:
                #     return [] unless context.visibility == :public
                #     [Docscribe::Plugin::Tag.new(name: 'api', text: 'public')]
                []
              end
            end
          RUBY
        end

        # Template for a CollectorPlugin.
        #
        # @private
        # @param [String] class_name
        # @return [String]
        def collector_template(class_name)
          <<~RUBY
            # frozen_string_literal: true

            require 'docscribe/plugin'
            require 'docscribe/infer/ast_walk'

            # #{class_name} — a Docscribe CollectorPlugin.
            #
            # CollectorPlugins receive the raw AST and source buffer for each file.
            # They walk the tree independently and return insertion targets that
            # Docscribe will document according to the selected strategy.
            #
            # Idempotency is handled automatically:
            #   :safe       — skips insertion if a comment already exists above anchor_node
            #   :aggressive — removes the existing comment and inserts a fresh block
            #
            # Use this plugin type for non-standard constructs that Docscribe's
            # built-in Collector does not recognize (DSL macros, define_method, etc.).
            # For ordinary +def+ methods use TagPlugin instead.
            #
            # @example Registration
            #   Docscribe::Plugin::Registry.register(#{class_name}.new)
            class #{class_name} < Docscribe::Plugin::Base::CollectorPlugin
              # Walk the AST and return documentation insertion targets.
              #
              # Each result must be a Hash with:
              #   :anchor_node — Parser::AST::Node above which to insert the doc block
              #   :doc         — String with the complete doc block (newlines included)
              #
              # Indentation is applied automatically from anchor_node — do not
              # prefix lines manually.
              #
              # @param [Parser::AST::Node] ast root AST node of the file
              # @param [Parser::Source::Buffer] buffer source buffer
              # @return [Array<Hash>]
              def collect(ast, buffer)
                results = []

                Docscribe::Infer::ASTWalk.walk(ast) do |node|
                  # TODO: replace with your target node detection
                  #
                  # Example — match bare send calls like `my_dsl_macro :name`:
                  #
                  #   next unless node.type == :send
                  #   recv, meth, name_node, *_rest = *node
                  #   next unless recv.nil? && meth == :my_dsl_macro
                  #   next unless name_node&.type == :sym
                  #
                  #   macro_name = name_node.children.first
                  #
                  #   results << {
                  #     anchor_node: node,
                  #     doc: "# \#{macro_name} — generated doc\\n# @return [void]\\n"
                  #   }
                end

                results
              end
            end
          RUBY
        end

        # Write generated plugin to a file or print to STDOUT based on options.
        #
        # @private
        # @param [String] content generated plugin source code
        # @param [String] plugin_type 'tag' or 'collector'
        # @param [String] class_name CamelCase plugin class name
        # @param [Hash] opts parsed options hash
        # @return [Integer] exit code
        def dispatch_output(content, plugin_type, class_name, opts)
          if opts[:stdout]
            puts content
            return 0
          end

          write_plugin(content, plugin_type: plugin_type, class_name: class_name, output_dir: opts[:output] || '.')
        end

        # Write the generated content to a file.
        #
        # @private
        # @param [String] content
        # @param [String] plugin_type
        # @param [String] class_name
        # @param [String] output_dir
        # @return [Integer] exit code
        def write_plugin(content, plugin_type:, class_name:, output_dir:)
          path = plugin_path(class_name, output_dir)

          return 1 if file_exists?(path)

          write_to_file(output_dir, path, content)
          print_created(plugin_type, path)
          0
        end

        # Build the OptionParser for the generate subcommand.
        #
        # @private
        # @param [Hash] opts mutable parsed options hash
        # @return [OptionParser]
        def build_option_parser(opts)
          OptionParser.new do |opt|
            opt.banner = parser_banner
            register_output_option(opt, opts)
            register_stdout_option(opt, opts)
            register_help_option(opt, opts)
          end
        end

        # Return the usage banner for the generate subcommand parser.
        #
        # @private
        # @return [String]
        def parser_banner
          <<~TEXT
            Usage: docscribe generate <type> <PluginName> [options]

            Types:
              tag         Generate a TagPlugin skeleton
              collector   Generate a CollectorPlugin skeleton

            Options:
          TEXT
        end

        # Register the --output option on the OptionParser.
        #
        # @private
        # @param [OptionParser] opt
        # @param [Hash] opts mutable parsed options hash
        # @return [void]
        def register_output_option(opt, opts)
          opt.on('--output DIR', 'Directory to write the plugin file (default: .)') { |v| opts[:output] = v }
        end

        # Register the --stdout option on the OptionParser.
        #
        # @private
        # @param [OptionParser] opt
        # @param [Hash] opts mutable parsed options hash
        # @return [void]
        def register_stdout_option(opt, opts)
          opt.on('--stdout', 'Print the generated plugin to STDOUT instead of writing a file') { opts[:stdout] = true }
        end

        # Register the -h/--help option on the OptionParser.
        #
        # @private
        # @param [OptionParser] opt
        # @param [Hash] opts mutable parsed options hash
        # @return [void]
        def register_help_option(opt, opts)
          opt.on('-h', '--help', 'Show this help') do
            opts[:help] = true
          end
        end

        # Validate that both plugin_type and class_name arguments were provided.
        #
        # @private
        # @param [String, nil] plugin_type plugin type argument
        # @param [String, nil] class_name plugin class name argument
        # @param [OptionParser] parser
        # @return [Boolean]
        def args_provided?(plugin_type, class_name, parser)
          return true if plugin_type && class_name

          warn 'Error: both <type> and <PluginName> are required.'
          warn parser
          false
        end

        # Validate that the plugin type is one of the recognized types.
        #
        # @private
        # @param [String] plugin_type plugin type to validate
        # @return [Boolean]
        def known_type?(plugin_type)
          return true if PLUGIN_TYPES.include?(plugin_type)

          warn "Error: unknown type #{plugin_type.inspect}. Must be one of: #{PLUGIN_TYPES.join(', ')}."
          false
        end

        # Validate that the class name is a valid Ruby constant name.
        #
        # @private
        # @param [String] class_name class name to validate
        # @return [Boolean]
        def valid_name?(class_name)
          return true if valid_constant?(class_name)

          warn "Error: #{class_name.inspect} is not a valid Ruby constant name."
          false
        end

        # Check whether a string is a valid Ruby constant name.
        #
        # @private
        # @param [String] str
        # @return [Boolean]
        def valid_constant?(str)
          !!(str =~ /\A[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*\z/)
        end

        # Build the file path for the generated plugin.
        #
        # @private
        # @param [String] class_name CamelCase plugin class name
        # @param [String] output_dir output directory
        # @return [String] full file path
        def plugin_path(class_name, output_dir)
          File.join(output_dir, "#{underscore(class_name)}.rb")
        end

        # Convert CamelCase to snake_case for file naming.
        #
        # @private
        # @param [String] str
        # @return [String]
        def underscore(str)
          str
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
        end

        # Check whether the target plugin file already exists and warn if so.
        #
        # @private
        # @param [String] path file path to check
        # @return [Boolean]
        def file_exists?(path)
          return false unless File.exist?(path)

          warn "Error: #{path} already exists. Remove it first or use --stdout."
          true
        end

        # Create the output directory and write the plugin file.
        #
        # @private
        # @param [String] output_dir output directory path
        # @param [String] path full plugin file path
        # @param [String] content file content to write
        # @return [void]
        def write_to_file(output_dir, path, content)
          require 'fileutils'
          FileUtils.mkdir_p(output_dir)
          File.write(path, content)
        end

        # Print the creation message and next steps after generating a plugin.
        #
        # @private
        # @param [String] plugin_type 'tag' or 'collector'
        # @param [String] path file path of the created plugin
        # @return [void]
        def print_created(plugin_type, path)
          puts "Created: #{path}"
          puts
          puts next_steps(plugin_type, path)
        end

        # Print registration instructions after file creation.
        #
        # @private
        # @param [String] plugin_type
        # @param [String] path
        # @return [String]
        def next_steps(plugin_type, path)
          format(NEXT_STEPS_TEMPLATE,
                 path: path,
                 hint: generate_implement_hint(plugin_type),
                 require_path: path.delete_suffix('.rb'),
                 base_name: plugin_base_name(path))
        end

        # Derive a CamelCase base name from a snake_case file path.
        #
        # @private
        # @param [String] path file path
        # @return [String] CamelCase class name
        def plugin_base_name(path)
          File.basename(path, '.rb').split('_').map(&:capitalize).join
        end

        # Generate an implementation hint string for the given plugin type.
        #
        # @private
        # @param [String] plugin_type 'tag' or 'collector'
        # @return [String] hint text
        def generate_implement_hint(plugin_type)
          case plugin_type
          when 'tag'
            'Implement the #call method to return Array<Docscribe::Plugin::Tag>.'
          when 'collector'
            'Implement the #collect method to return Array<{anchor_node:, doc:}>.'
          end
        end
      end
    end
  end
end
