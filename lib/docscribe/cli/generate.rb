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

      class << self
        # Run the `generate` subcommand.
        #
        # @param [Array<String>] argv
        # @raise [OptionParser::InvalidOption]
        # @return [Integer] exit code
        def run(argv)
          opts = {
            output: nil,
            stdout: false
          }

          parser = OptionParser.new do |o|
            o.banner = <<~TEXT
              Usage: docscribe generate <type> <PluginName> [options]

              Types:
                tag         Generate a TagPlugin skeleton
                collector   Generate a CollectorPlugin skeleton

              Options:
            TEXT

            o.on('--output DIR', 'Directory to write the plugin file (default: .)') { |v| opts[:output] = v }
            o.on('--stdout', 'Print the generated plugin to STDOUT instead of writing a file') { opts[:stdout] = true }
            o.on('-h', '--help', 'Show this help') do
              puts o
              return 0
            end
          end

          begin
            parser.parse!(argv)
          rescue OptionParser::InvalidOption => e
            warn e.message
            warn parser
            return 1
          end

          plugin_type = argv.shift
          class_name  = argv.shift

          unless plugin_type && class_name
            warn 'Error: both <type> and <PluginName> are required.'
            warn parser
            return 1
          end

          unless PLUGIN_TYPES.include?(plugin_type)
            warn "Error: unknown type #{plugin_type.inspect}. Must be one of: #{PLUGIN_TYPES.join(', ')}."
            return 1
          end

          unless valid_constant?(class_name)
            warn "Error: #{class_name.inspect} is not a valid Ruby constant name."
            return 1
          end

          content = render(plugin_type, class_name)

          if opts[:stdout]
            puts content
            return 0
          end

          write_plugin(content, plugin_type: plugin_type, class_name: class_name, output_dir: opts[:output] || '.')
        end

        private

        # Check whether a string is a valid Ruby constant name.
        #
        # @private
        # @param [String] str
        # @return [Boolean]
        def valid_constant?(str)
          !!(str =~ /\A[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*\z/)
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

        # Write the generated content to a file.
        #
        # @private
        # @param [String] content
        # @param [String] plugin_type
        # @param [String] class_name
        # @param [String] output_dir
        # @return [Integer] exit code
        def write_plugin(content, plugin_type:, class_name:, output_dir:)
          filename = "#{underscore(class_name)}.rb"
          path     = File.join(output_dir, filename)

          if File.exist?(path)
            warn "Error: #{path} already exists. Remove it first or use --stdout."
            return 1
          end

          require 'fileutils'
          FileUtils.mkdir_p(output_dir)
          File.write(path, content)
          puts "Created: #{path}"
          puts
          puts next_steps(plugin_type, path)
          0
        end

        # Print registration instructions after file creation.
        #
        # @private
        # @param [String] plugin_type
        # @param [String] path
        # @return [String]
        def next_steps(plugin_type, path)
          base_name = File.basename(path, '.rb').split('_').map(&:capitalize).join

          implement_hint = case plugin_type
                           when 'tag'
                             'Implement the #call method to return Array<Docscribe::Plugin::Tag>.'
                           when 'collector'
                             'Implement the #collect method to return Array<{anchor_node:, doc:}>.'
                           end

          <<~TEXT
            Next steps:
              1. Open #{path} and implement the plugin logic.
                 #{implement_hint}

              2. Register the plugin in your docscribe_plugins.rb:

                   require_relative '#{path.delete_suffix('.rb')}'
                   Docscribe::Plugin::Registry.register(#{base_name}.new)

              3. Add the file to docscribe.yml:

                   plugins:
                     require:
                       - ./docscribe_plugins
          TEXT
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
      end
    end
  end
end
