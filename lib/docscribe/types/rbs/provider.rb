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
        # @param [Boolean] collapse_object_generics collapse Object generics flag
        # @return [void]
        def initialize(sig_dirs:, collection_dirs: [], collapse_generics: false, collapse_object_generics: false)
          require 'rbs'
          @sig_dirs = Array(sig_dirs).map(&:to_s)
          @collection_dirs = Array(collection_dirs).map(&:to_s)
          @collapse_generics = !!collapse_generics
          @collapse_object_generics = !!collapse_object_generics
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
          return nil unless definition

          method_def = definition.methods[name.to_sym]
          return nil unless method_def

          method_type = method_def.method_types.first
          return nil unless method_type

          func = method_type.type #: ::RBS::Types::Function
          build_signature(func)
        end

        # Try building an environment from combined dirs, falling back to
        # user-only dirs on failure when collection dirs are present.
        #
        # @private
        # @param [Array<String>] all_dirs combined sig and collection dirs
        # @param [Array<String>] collection_dirs RBS collection directories
        # @raise [::RBS::BaseError]
        # @raise [StandardError]
        # @return [RBS::Environment]
        def try_with_fallback_build_env(all_dirs, collection_dirs)
          # First attempt: load core types + all dirs (sig + collection).
          # If duplicate declarations occur (stdlib gem in both `library: 'rbs'`
          # and collection), retry with individual collection gem dirs,
          # skipping those already provided by the rbs stdlib.
          build_env_with_collection(all_dirs, collection_dirs)
        rescue ::RBS::BaseError => e
          raise unless collection_dirs.any? && !@collection_dropped

          @collection_dropped = true
          warn "Docscribe: RBS collection error (#{e.class}), dropping collection dirs. " \
               'Set DOCSCRIBE_RBS_DEBUG=1 for details.'
          build_env(@sig_dirs)
        end

        # Build the environment, handling potential duplicate declarations
        # between rbs stdlib and collection gems.
        #
        # @private
        # @param [Array<String>] all_dirs combined sig and collection dirs
        # @param [Array<String>] collection_dirs RBS collection directories
        # @return [RBS::Environment]
        def build_env_with_collection(all_dirs, collection_dirs)
          loader = ::RBS::EnvironmentLoader.new
          loader.add(library: 'rbs') # steep:ignore
          add_dirs_to_loader!(loader, all_dirs, collection_dirs)
          env = ::RBS::Environment.from_loader(loader).resolve_type_names
          @builder = ::RBS::DefinitionBuilder.new(env: env)
          env
        end

        # Add directories to the loader, handling collection dirs separately.
        #
        # @private
        # @param [RBS::EnvironmentLoader] loader
        # @param [Array<String>] all_dirs
        # @param [Array<String>] collection_dirs
        # @return [void]
        def add_dirs_to_loader!(loader, all_dirs, collection_dirs)
          stdlib = stdlib_gem_names
          all_dirs.each do |dir|
            path = Pathname(dir)
            next unless path.directory?

            if collection_dirs.include?(dir)
              add_collection_gem_dirs(loader, path, stdlib)
            else
              loader.add(path: path)
            end
          end
        end

        # Add individual collection gem directories to the loader.
        #
        # @private
        # @param [RBS::EnvironmentLoader] loader
        # @param [Pathname] path
        # @param [Array<String>] stdlib
        # @return [void]
        def add_collection_gem_dirs(loader, path, stdlib)
          path.children.each do |child|
            next unless child.directory?
            next if stdlib.include?(child.basename.to_s)

            loader.add(path: child)
          end
        end

        # Names of stdlib gems bundled with the `rbs` gem.
        #
        # @private
        # @raise [StandardError]
        # @return [Array<String>] if StandardError
        # @return [Array] if StandardError
        def stdlib_gem_names
          rbs_spec = Gem::Specification.find_by_name('rbs')
          stdlib_dir = File.join(rbs_spec.gem_dir, 'stdlib')
          Dir.children(stdlib_dir)
        rescue StandardError
          []
        end

        # Build an RBS environment from the given directories.
        #
        # @private
        # @param [Array<String>] dirs directories to load RBS from
        # @return [RBS::Environment]
        def build_env(dirs)
          loader = ::RBS::EnvironmentLoader.new
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
        # @return [RBS::Definition, nil]
        def definition_for(container:, scope:)
          container = container.sub(/\[.*\]/, '').sub(/<.*>/, '')
          type_name = parse_type_name(absolute_const(container))
          return nil unless @builder&.env&.type_name?(type_name)

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
        # @param [RBS::Types::Function] func RBS function type to convert
        # @return [Docscribe::Types::MethodSignature]
        def build_signature(func)
          param_types, positional_types = build_param_types(func)
          MethodSignature.new(
            return_type: format_type(func.return_type),
            param_types: param_types,
            positional_types: positional_types,
            rest_positional: build_rest_positional(func),
            rest_keywords: build_rest_keywords(func)
          )
        end

        # Build a name => type map and positional type list for all
        # positional and keyword parameters.
        #
        # Returns [param_types (Hash), positional_types (Array)].
        # positional_types includes ALL positional params in order (named
        # and unnamed) so callers can fall back to positional matching when
        # the RBS signature omits parameter names.
        #
        # @private
        # @param [RBS::Types::Function] func RBS function to extract params
        # @return [(Hash<String, String>, Array<String>)]
        def build_param_types(func)
          param_types = {} #: Hash[String, String]
          positional_types = [] #: Array[String]

          collect_positionals!(param_types, positional_types, func.required_positionals)
          collect_positionals!(param_types, positional_types, func.optional_positionals)
          collect_positionals!(param_types, positional_types, func.trailing_positionals)

          add_keywords!(param_types, func.required_keywords)
          add_keywords!(param_types, func.optional_keywords)

          [param_types, positional_types]
        end

        # Add keyword parameters to the normalized parameter map.
        #
        # @private
        # @param [Hash<String, String>] param_types normalized param type map
        # @param [Hash<Symbol, RBS::Types::Function::Param>] keywords keyword parameter entries
        # @return [void]
        def add_keywords!(param_types, keywords)
          keywords.each do |kw, p|
            param_types[kw.to_s] = format_type(p.type)
          end
        end

        # Collect positional parameter types into both the name-keyed hash
        # (when a name is available) and the ordered-position list (always).
        #
        # @private
        # @param [Hash<String, String>] param_types normalized param type map
        # @param [Array<String>] positional_types ordered type list
        # @param [Array<RBS::Types::Function::Param>] list positional parameter objects
        # @return [void]
        def collect_positionals!(param_types, positional_types, list)
          list.each do |p|
            type_str = format_type(p.type)
            positional_types << type_str
            param_types[p.name.to_s] = type_str if p.name
          end
        end

        # Build normalized `*args` metadata.
        #
        # @private
        # @param [RBS::Types::Function] func RBS function for rest params
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
        # @param [RBS::Types::Function] func RBS function for rest keywords
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
        # @param [Docscribe::Types::RBS::TypeFormatter::rbs_type] type RBS type object to format
        # @return [String]
        def format_type(type)
          Docscribe::Types::RBS::TypeFormatter.to_yard(
            type,
            collapse_generics: @collapse_generics,
            collapse_object_generics: @collapse_object_generics
          )
        end

        # Emit a formatted RBS error warning with context-specific messaging.
        #
        # @private
        # @param [RBS::BaseError, StandardError] error the raised exception
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

        # Print one warning per provider instance (avoiding repeated spam).
        #
        # @private
        # @param [String] msg warning message text
        # @return [void]
        def warn_once(msg)
          return if @warned

          @warned = true
          warn msg
        end
      end
    end
  end
end
