# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/rbs_type_formatter'

module Docscribe
  module Types
    # Provides RBS-backed method signatures for Docscribe.
    #
    # This class loads RBS signatures from one or more `sig` directories, resolves
    # class/module definitions, and returns a simplified signature object that the
    # doc generator can use to render `@param` and `@return`.
    #
    # Behavior notes:
    # - If RBS cannot be loaded, signatures cannot be resolved, or no signature is found
    #   for a method, this provider returns nil and Docscribe falls back to inference.
    # - If a method has multiple overloads, Docscribe currently uses the *first* overload.
    #
    # Debugging:
    # - Set `DOCSCRIBE_RBS_DEBUG=1` to print a one-time warning when RBS integration fails.
    class RBSProvider
      # A simplified view of a method signature for Docscribe.
      #
      # @!attribute return_type
      #   @return [String] YARD-compatible return type (e.g. "Integer", "Hash<Symbol, Object>")
      # @!attribute param_types
      #   @return [Hash{String=>String}] Mapping of parameter name to YARD type
      # @!attribute rest_positional
      #   @return [RestPositional, nil] Info about `*args`
      # @!attribute rest_keywords
      #   @return [RestKeywords, nil] Info about `**kwargs`
      Signature = Struct.new(:return_type, :param_types, :rest_positional, :rest_keywords, keyword_init: true)

      # @!attribute name
      #   @return [String, nil] Name of `*args` in RBS, if present
      # @!attribute element_type
      #   @return [String] YARD type for element type (e.g. "String")
      RestPositional = Struct.new(:name, :element_type, keyword_init: true)

      # @!attribute name
      #   @return [String, nil] Name of `**kwargs` in RBS, if present
      # @!attribute type
      #   @return [String] YARD type for kwargs type (often a Hash-like type)
      RestKeywords = Struct.new(:name, :type, keyword_init: true)

      # Create a provider.
      #
      # @param sig_dirs [Array<String>] directories containing `.rbs` files (e.g. ["sig"])
      # @param collapse_generics [Boolean] when true, collapse generic args (`Hash<...>` -> `Hash`)
      def initialize(sig_dirs:, collapse_generics: false)
        require 'rbs'

        @sig_dirs = Array(sig_dirs).map(&:to_s)
        @collapse_generics = !!collapse_generics

        @env = nil
        @builder = nil
        @warned = false
      end

      # Return an RBS-backed signature for a method, or nil.
      #
      # @param container [String] constant name (e.g. "MyApp::User")
      # @param scope [Symbol] :instance or :class
      # @param name [String, Symbol] method name
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

      # Lazily load and build the RBS environment.
      #
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

      # Build a definition object for a container and scope.
      #
      # @param container [String]
      # @param scope [Symbol] :instance or :class
      # @return [RBS::Definition]
      def definition_for(container:, scope:)
        type_name = RBS::TypeName.parse(absolute_const(container))
        scope == :class ? @builder.build_singleton(type_name) : @builder.build_instance(type_name)
      end

      # Convert an RBS container name into an absolute constant string.
      #
      # @param container [String]
      # @return [String] e.g. "::Foo::Bar"
      def absolute_const(container)
        s = container.to_s
        s.start_with?('::') ? s : "::#{s}"
      end

      # Build Docscribe's simplified signature from an RBS function type.
      #
      # @param func [RBS::Types::Function]
      # @return [Signature]
      def build_signature(func)
        Signature.new(
          return_type: format_type(func.return_type),
          param_types: build_param_types(func),
          rest_positional: build_rest_positional(func),
          rest_keywords: build_rest_keywords(func)
        )
      end

      # Build param name => type map from an RBS function type.
      #
      # @param func [RBS::Types::Function]
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

      # Add named positionals to the param_types map.
      #
      # @param param_types [Hash{String=>String}]
      # @param list [Array<#name,#type>]
      # @return [void]
      def add_positionals!(param_types, list)
        list.each do |p|
          next unless p.name

          param_types[p.name.to_s] = format_type(p.type)
        end
      end

      # Build rest positional info for `*args`.
      #
      # @param func [RBS::Types::Function]
      # @return [RestPositional, nil]
      def build_rest_positional(func)
        rp = func.rest_positionals
        return nil unless rp

        RestPositional.new(
          name: rp.name&.to_s,
          element_type: format_type(rp.type)
        )
      end

      # Build rest keywords info for `**kwargs`.
      #
      # @param func [RBS::Types::Function]
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
      # @param type [Object]
      # @return [String]
      def format_type(type)
        RBSTypeFormatter.to_yard(type, collapse_generics: @collapse_generics)
      end

      # Print a one-time warning when RBS is enabled but fails.
      #
      # Only prints when DOCSCRIBE_RBS_DEBUG=1.
      #
      # @param msg [String]
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
