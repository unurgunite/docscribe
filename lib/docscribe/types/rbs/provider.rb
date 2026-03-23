# frozen_string_literal: true

require 'docscribe/types/signature'
require 'docscribe/types/rbs/type_formatter'
require 'docscribe/types/provider_chain'

module Docscribe
  module Types
    module RBS
      # Provides RBS-backed method signatures for Docscribe.
      #
      # This class loads RBS signatures from one or more signature directories,
      # resolves class/module definitions, and returns a simplified signature object
      # suitable for generating YARD-style `@param` and `@return` tags.
      #
      # Behavior notes:
      # - If RBS cannot be loaded, signatures cannot be resolved, or no matching method is found,
      #   this provider returns nil and Docscribe falls back to inference.
      # - If a method has multiple overloads, the first overload is currently used.
      #
      # Debugging:
      # - Set `DOCSCRIBE_RBS_DEBUG=1` to print a one-time warning when RBS integration fails.
      class Provider < ::Docscribe::Types::ProviderChain
        # Initialize an RBS provider.
        #
        # @param [Array<String>] sig_dirs signature directories to load
        # @param [Boolean] collapse_generics whether generic RBS types should be simplified
        # @return [void]
        def initialize(sig_dirs:, collapse_generics: false)
          require 'rbs'

          @sig_dirs = Array(sig_dirs).map(&:to_s)
          @collapse_generics = !!collapse_generics

          @env = nil
          @builder = nil
          @warned = false
        end

        # Resolve a method signature for a container/scope/name triple.
        #
        # Returns nil if no matching method is found or if RBS resolution fails.
        #
        # @param [String] container class or module name, e.g. `"MyApp::Service"`
        # @param [Symbol] scope :instance or :class
        # @param [String, Symbol] name method name
        # @raise [RBS::ParsingError]
        # @raise [RBS::DefinitionBuilder::UnknownTypeNameError]
        # @raise [StandardError]
        # @raise [RBS::BaseError]
        # @return [Signature, nil]
        def signature_for(container:, scope:, name:)
          load_env!

          definition = definition_for(container: container, scope: scope)
          method_def = definition.methods[name.to_sym]
          return nil unless method_def

          method_type = method_def.method_types.first
          return nil unless method_type

          func = method_type.type # RBS::Types::Function
          build_signature(func)
        rescue RBS::BaseError => e
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

        # Convert an RBS function type into a simplified Docscribe signature.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Signature]
        def build_signature(func)
          MethodSignature.new(
            return_type: format_type(func.return_type),
            param_types: build_param_types(func),
            rest_positional: build_rest_positional(func),
            rest_keywords: build_rest_keywords(func)
          )
        end

        # Build a name-to-type mapping for explicit positional and keyword parameters.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [Hash{String=>String}]
        def build_param_types(func)
          param_types = {}

          add_positionals!(param_types, func.required_positionals)
          add_positionals!(param_types, func.optional_positionals)
          add_positionals!(param_types, func.trailing_positionals)

          func.required_keywords.each { |kw, p| param_types[kw.to_s] = format_type(p.type) }
          func.optional_keywords.each { |kw, p| param_types[kw.to_s] = format_type(p.type) }

          param_types
        end

        # Add named positional parameters into a param type map.
        #
        # Anonymous positional parameters are ignored.
        #
        # @private
        # @param [Hash{String=>String}] param_types
        # @param [Array<Object>] list
        # @return [void]
        def add_positionals!(param_types, list)
          list.each do |p|
            next unless p.name

            param_types[p.name.to_s] = format_type(p.type)
          end
        end

        # Build simplified rest-positional info from an RBS function.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [RestPositional, nil]
        def build_rest_positional(func)
          rp = func.rest_positionals
          return nil unless rp

          RestPositional.new(
            name: rp.name&.to_s,
            element_type: format_type(rp.type)
          )
        end

        # Build simplified rest-keyword info from an RBS function.
        #
        # @private
        # @param [RBS::Types::Function] func
        # @return [RestKeywords, nil]
        def build_rest_keywords(func)
          rk = func.rest_keywords
          return nil unless rk

          RestKeywords.new(
            name: rk.name&.to_s,
            type: format_type(rk.type)
          )
        end

        # Format an RBS type into a YARD-ish string.
        #
        # @private
        # @param [Object] type
        # @return [String]
        def format_type(type)
          Docscribe::Types::RBS::TypeFormatter.to_yard(type, collapse_generics: @collapse_generics)
        end

        # Print one debug warning at most when RBS debugging is enabled.
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
