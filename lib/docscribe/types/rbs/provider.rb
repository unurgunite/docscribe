# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/signature'
require 'docscribe/types/rbs/type_formatter'
require 'docscribe/types/rbs/collection_loader'

module Docscribe
  module Types
    module RBS
      # Resolve method signatures from `.rbs` files using the official RBS
      # environment and definition builder APIs.
      #
      # The provider returns Docscribe's normalized signature model so the rest of
      # the pipeline can stay independent of the underlying signature source.
      class Provider
        # Initialize
        #
        # @param [Array<String>] sig_dirs directories containing `.rbs` files
        # @param [Array<String>] collection_dirs RBS collection directories
        # @param [Boolean] collapse_generics whether generic container types
        # @return [void]
        def initialize(sig_dirs:, collection_dirs: [], collapse_generics: false)
          require 'rbs'
          @sig_dirs = Array(sig_dirs).map(&:to_s)
          @collection_dirs = Array(collection_dirs).map(&:to_s)
          @collapse_generics = !!collapse_generics
          @env = nil
          @builder = nil
          @warned = false
          @collection_dropped = false
        end

        # Look up a normalized method signature from loaded RBS definitions.
        #
        # Returns nil when the method cannot be resolved or when RBS lookup fails.
        #
        # @param [String] container e.g. "MyModule::MyClass"
        # @param [Symbol] scope :instance or :class
        # @param [Symbol, String] name method name
        # @raise [::RBS::BaseError]
        # @raise [StandardError]
        # @return [Docscribe::Types::MethodSignature, nil] if StandardError
        # @return [nil] if ::RBS::BaseError
        # @return [nil] if StandardError
        def signature_for(container:, scope:, name:)
          load_env!
          lookup_signature(container, scope, name)
        rescue ::RBS::BaseError => e
          handle_rbs_error(e, 'RBS error')
          nil
        rescue StandardError => e
          handle_rbs_error(e, 'RBS integration failed (falling back to inference)')
          nil
        end

        private

        # Lazily load and resolve the RBS environment.
        #
        # Tries to load collection dirs together with user sig_dirs.
        # If the combined environment raises a load error (e.g. duplicate
        # declarations between collection and core stdlib types), collection
        # dirs are dropped and only user sig_dirs are used.
        #
        # @private
        # @return [void]
        def load_env!
          return if @env && @builder

          @env = try_with_fallback_build_env(
            @sig_dirs + @collection_dirs,
            @collection_dirs
          )
        end

        # Look up a method signature from the loaded RBS definition builder.
        #
        # @private
        # @param [String] container fully qualified class/module name
        # @param [Symbol] scope :instance or :class
        # @param [Symbol, String] name method name to look up
        # @return [Docscribe::Types::MethodSignature, nil]
        def lookup_signature(container, scope, name)
          definition = definition_for(container: container, scope: scope)
          method_def = definition.methods[name.to_sym]
          return nil unless method_def

          method_type = method_def.method_types.first
          return nil unless method_type

          build_signature(method_type.type)
        end

        # Try building an environment from combined dirs, falling back to
        # user-only dirs on failure when collection dirs are present.
        #
        # @private
        # @param [Array<String>] all_dirs combined sig and collection dirs
        # @param [Array<String>] collection_dirs RBS collection directories
        # @raise [::RBS::BaseError]
        # @raise [StandardError]
        # @return [RBS::Environment] if ::RBS::BaseError
        # @return [Object] if ::RBS::BaseError
        def try_with_fallback_build_env(all_dirs, collection_dirs)
          build_env(all_dirs)
        rescue ::RBS::BaseError => e
          raise unless collection_dirs.any? && !@collection_dropped

          @collection_dropped = true
          if ENV['DOCSCRIBE_RBS_DEBUG'] == '1'
            warn "Docscribe: RBS collection error (#{e.class}), dropping collection dirs. " \
                 'Set DOCSCRIBE_RBS_DEBUG=1 for details.'
          end
          build_env(@sig_dirs)
        end

        # Build an RBS environment from the given directories.
        #
        # @private
        # @param [Array<String>] dirs
        # @return [RBS::Environment]
        def build_env(dirs)
          loader = ::RBS::EnvironmentLoader.new
          # Load core types transitively
          loader.add(library: 'rbs') # steep:ignore

          dirs.each do |dir|
            path = Pathname(dir)
            loader.add(path: path) if path.directory?
          end

          env = ::RBS::Environment.from_loader(loader).resolve_type_names
          @builder = ::RBS::DefinitionBuilder.new(env: env)
          env
        end

        # Build the appropriate instance or singleton definition for a container.
        #
        # @private
        # @param [String] container fully qualified class/module name
        # @param [Symbol] scope :instance or :class
        # @return [Object]
        def definition_for(container:, scope:)
          type_name = parse_type_name(absolute_const(container))
          scope == :class ? @builder&.build_singleton(type_name) : @builder&.build_instance(type_name)
        end

        # Parse a fully-qualified constant string into an RBS TypeName.
        #
        # Uses the lower-level constructor so it works across RBS versions
        # that may not expose `TypeName.parse`.
        #
        # @private
        # @param [String] string e.g. "::Irb::Autosuggestions"
        # @return [RBS::TypeName]
        def parse_type_name(string)
          absolute = string.start_with?('::')
          *path, name = string.delete_prefix('::').split('::').map(&:to_sym)
          name ||= :Object
          ::RBS::TypeName.new(
            name: name,
            namespace: ::RBS::Namespace.new(path: path, absolute: absolute)
          )
        end

        # Normalize a container name into an absolute constant path.
        #
        # @private
        # @param [String] container fully qualified class/module name
        # @return [String]
        def absolute_const(container)
          s = container.to_s
          s.start_with?('::') ? s : "::#{s}"
        end

        # Convert an RBS function type into Docscribe's simplified signature
        # model.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Docscribe::Types::MethodSignature]
        def build_signature(func)
          MethodSignature.new(
            return_type: format_type(func.return_type),
            param_types: build_param_types(func),
            rest_positional: build_rest_positional(func),
            rest_keywords: build_rest_keywords(func)
          )
        end

        # Build a name => type map for positional and keyword parameters.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Hash<String, String>]
        def build_param_types(func)
          param_types = {} #: Hash[String, String]

          add_positionals!(param_types, func.required_positionals)
          add_positionals!(param_types, func.optional_positionals)
          add_positionals!(param_types, func.trailing_positionals)

          add_keywords!(param_types, func.required_keywords)
          add_keywords!(param_types, func.optional_keywords)

          param_types
        end

        # Add keyword parameters to the normalized parameter map.
        #
        # @private
        # @param [Hash<String, String>] param_types
        # @param [Hash<Symbol, Object>] keywords
        # @return [void]
        def add_keywords!(param_types, keywords)
          keywords.each do |kw, p|
            param_types[kw.to_s] = format_type(p.type)
          end
        end

        # Add named positional parameters to the normalized parameter map.
        #
        # @private
        # @param [Hash<String, String>] param_types
        # @param [Array<Object>] list
        # @return [void]
        def add_positionals!(param_types, list)
          list.each do |p|
            next unless p.name

            param_types[p.name.to_s] = format_type(p.type)
          end
        end

        # Build normalized `*args` metadata.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Docscribe::Types::RestPositional, nil]
        def build_rest_positional(func)
          rp = func.rest_positionals
          return nil unless rp

          RestPositional.new(
            name: rp.name&.to_s,
            element_type: format_type(rp.type)
          )
        end

        # Build normalized `**kwargs` metadata.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Docscribe::Types::RestKeywords, nil]
        def build_rest_keywords(func)
          rk = func.rest_keywords
          return nil unless rk

          RestKeywords.new(
            name: rk.name&.to_s,
            type: format_type(rk.type)
          )
        end

        # Format an RBS type object into the YARD-ish type syntax used by
        # generated comments.
        #
        # @private
        # @param [Object] type
        # @return [String]
        def format_type(type)
          Docscribe::Types::RBS::TypeFormatter.to_yard(
            type,
            collapse_generics: @collapse_generics
          )
        end

        # Emit a formatted RBS error warning with context-specific messaging.
        #
        # @private
        # @param [Object] error the raised exception
        # @param [String] context human-readable context label
        # @return [void]
        def handle_rbs_error(error, context)
          case error
          when ::RBS::BaseError
            warn_once("Docscribe: #{context}: #{error.class}: #{error.message}")
          else
            warn_once(
              "Docscribe: #{context}: #{error.class}: #{error.message}\n" \
              'Feel free to open an issue on github.'
            )
          end
        end

        # Print one debug warning per provider instance when debugging is enabled.
        #
        # @private
        # @param [String] msg
        # @return [void]
        def warn_once(msg)
          return unless ENV['DOCSCRIBE_RBS_DEBUG'] == '1'
          return if @warned

          @warned = true
          warn msg
        end
      end
    end
  end
end
