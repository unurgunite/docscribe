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
        # @param [Array<String>] sig_dirs directories containing `.rbs` files
        # @param [Boolean] collapse_generics whether generic container types
        #   should be simplified during formatting
        # @return [Object]
        def initialize(sig_dirs:, collapse_generics: false)
          require 'rbs'
          @sig_dirs = Array(sig_dirs).map(&:to_s)
          @collapse_generics = !!collapse_generics
          @env = nil
          @builder = nil
          @warned = false
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
        # @return [Docscribe::Types::MethodSignature, nil]
        def signature_for(container:, scope:, name:)
          load_env!

          definition = definition_for(container: container, scope: scope)
          method_def = definition.methods[name.to_sym]
          return nil unless method_def

          method_type = method_def.method_types.first
          return nil unless method_type

          func = method_type.type
          build_signature(func)
        rescue ::RBS::BaseError => e
          warn_once("Docscribe: RBS error: #{e.class}: #{e.message}")
          nil
        rescue StandardError => e
          warn_once(
            'Docscribe: RBS integration failed (falling back to inference): ' \
            "#{e.class}: #{e.message}\nFeel free to open an issue on github."
          )
          nil
        end

        private

        # Lazily load and resolve the RBS environment.
        #
        # @private
        # @return [void]
        def load_env!
          return if @env && @builder

          loader = ::RBS::EnvironmentLoader.new
          # Load core types transitively
          loader.add(library: 'rbs')

          @sig_dirs.each do |dir|
            path = Pathname(dir)
            loader.add(path: path) if path.directory?
          end

          @env = ::RBS::Environment.from_loader(loader).resolve_type_names
          @builder = ::RBS::DefinitionBuilder.new(env: @env)
        end

        # Build the appropriate instance or singleton definition for a container.
        #
        # @private
        # @param [String] container
        # @param [Symbol] scope
        # @return [Object]
        def definition_for(container:, scope:)
          type_name = ::RBS::TypeName.parse(absolute_const(container))
          scope == :class ? @builder.build_singleton(type_name) : @builder.build_instance(type_name)
        end

        # Normalize a container name into an absolute constant path.
        #
        # @private
        # @param [String] container
        # @return [String]
        def absolute_const(container)
          s = container.to_s
          s.start_with?('::') ? s : "::#{s}"
        end

        # Convert an RBS function type into Docscribe's simplified signature
        # model.
        #
        # @private
        # @param [::RBS::Types::Function] func
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
        # @param [::RBS::Types::Function] func
        # @return [Hash{String => String}]
        def build_param_types(func)
          param_types = {}

          add_positionals!(param_types, func.required_positionals)
          add_positionals!(param_types, func.optional_positionals)
          add_positionals!(param_types, func.trailing_positionals)

          func.required_keywords.each do |kw, p|
            param_types[kw.to_s] = format_type(p.type)
          end

          func.optional_keywords.each do |kw, p|
            param_types[kw.to_s] = format_type(p.type)
          end

          param_types
        end

        # Add named positional parameters to the normalized parameter map.
        #
        # @private
        # @param [Hash{String => String}] param_types
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
        # @param [::RBS::Types::Function] func
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
        # @param [::RBS::Types::Function] func
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
