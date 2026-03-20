# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/rbs_type_formatter'

module Docscribe
  module Types
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
    class RBSProvider
      # Simplified view of an RBS method signature for Docscribe.
      #
      # @!attribute return_type
      #   @return [String] formatted return type for YARD output
      # @!attribute param_types
      #   @return [Hash{String=>String}] mapping of parameter name to formatted type
      # @!attribute rest_positional
      #   @return [RestPositional, nil] info for `*args`
      # @!attribute rest_keywords
      #   @return [RestKeywords, nil] info for `**kwargs`
      Signature = Struct.new(:return_type, :param_types, :rest_positional, :rest_keywords, keyword_init: true)

      # Simplified representation of an RBS rest-positional parameter.
      #
      # @!attribute name
      #   @return [String, nil] parameter name in RBS, if present
      # @!attribute element_type
      #   @return [String] formatted element type
      RestPositional = Struct.new(:name, :element_type, keyword_init: true)

      # Simplified representation of an RBS rest-keyword parameter.
      #
      # @!attribute name
      #   @return [String, nil] parameter name in RBS, if present
      # @!attribute type
      #   @return [String] formatted kwargs type
      RestKeywords = Struct.new(:name, :type, keyword_init: true)

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
      rescue RBS::ParsingError, RBS::DefinitionBuilder::UnknownTypeNameError => e
        warn_once("Docscribe: RBS error: #{e.class}: #{e.message}")
        nil
      rescue StandardError => e
        warn_once("Docscribe: RBS integration failed (falling back to inference): #{e.class}: #{e.message}")
        nil
      end

      private

      # Lazily load and resolve the RBS environment and definition builder.
      #
      # @private
      # @return [void]
      def load_env!
        return if @env && @builder

        loader = RBS::EnvironmentLoader.new
        @sig_dirs.each do |dir|
          path = Pathname(dir)
          loader.add(path: path) if path.directory?
        end

        @env = RBS::Environment.from_loader(loader).resolve_type_names
        @builder = RBS::DefinitionBuilder.new(env: @env)
      end

      # Resolve the RBS definition object for a given container and scope.
      #
      # @private
      # @param [String] container
      # @param [Symbol] scope :instance or :class
      # @return [Object]
      def definition_for(container:, scope:)
        type_name = RBS::TypeName.parse(absolute_const(container))
        scope == :class ? @builder.build_singleton(type_name) : @builder.build_instance(type_name)
      end

      # Normalize a container name into an absolute RBS constant name.
      #
      # @private
      # @param [String] container
      # @return [String]
      def absolute_const(container)
        s = container.to_s
        s.start_with?('::') ? s : "::#{s}"
      end

      # Convert an RBS function type into a simplified Docscribe signature.
      #
      # @private
      # @param [RBS::Types::Function] func
      # @return [Signature]
      def build_signature(func)
        Signature.new(
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
        RBSTypeFormatter.to_yard(type, collapse_generics: @collapse_generics)
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
