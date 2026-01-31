# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/rbs_type_formatter'

module Docscribe
  module Types
    class RBSProvider
      Signature = Struct.new(:return_type, :param_types, :rest_positional, :rest_keywords, keyword_init: true)
      RestPositional = Struct.new(:name, :element_type, keyword_init: true)
      RestKeywords = Struct.new(:name, :type, keyword_init: true)

      # +Docscribe::Types::RBSProvider#initialize+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] sig_dirs Param documentation.
      # @return [Object]
      def initialize(sig_dirs:, collapse_generics: false)
        require 'rbs'

        @sig_dirs = Array(sig_dirs).map(&:to_s)
        @collapse_generics = !!collapse_generics
        @env = nil
        @builder = nil
      end

      # +Docscribe::Types::RBSProvider#signature_for+ -> Signature
      #
      # Method documentation.
      #
      # @param [Object] container Param documentation.
      # @param [Object] scope Param documentation.
      # @param [Object] name Param documentation.
      # @raise [RBS::ParsingError]
      # @raise [RBS::DefinitionBuilder::UnknownTypeNameError]
      # @raise [StandardError]
      # @return [Signature]
      # @return [nil] if RBS::ParsingError, RBS::DefinitionBuilder::UnknownTypeNameError
      # @return [nil] if StandardError
      def signature_for(container:, scope:, name:)
        load_env!

        type_name = RBS::TypeName.parse(absolute_const(container)) # "::Foo::Bar"
        definition =
          if scope == :class
            @builder.build_singleton(type_name)
          else
            @builder.build_instance(type_name)
          end

        method = definition.methods[name.to_sym]
        return nil unless method

        method_type = method.method_types.first
        return nil unless method_type

        func = method_type.type # RBS::Types::Function
        return_type = RBSTypeFormatter.to_yard(func.return_type, collapse_generics: @collapse_generics)

        param_types = {}

        func.required_positionals.each do |p|
          if p.name
            param_types[p.name.to_s] =
              RBSTypeFormatter.to_yard(p.type, collapse_generics: @collapse_generics)
          end
        end
        func.optional_positionals.each do |p|
          if p.name
            param_types[p.name.to_s] =
              RBSTypeFormatter.to_yard(p.type, collapse_generics: @collapse_generics)
          end
        end
        func.trailing_positionals.each do |p|
          if p.name
            param_types[p.name.to_s] =
              RBSTypeFormatter.to_yard(p.type, collapse_generics: @collapse_generics)
          end
        end

        func.required_keywords.each do |kw, p|
          param_types[kw.to_s] = RBSTypeFormatter.to_yard(p.type,  collapse_generics: @collapse_generics)
        end
        func.optional_keywords.each do |kw, p|
          param_types[kw.to_s] = RBSTypeFormatter.to_yard(p.type,  collapse_generics: @collapse_generics)
        end

        rest_positional = nil
        if (rp = func.rest_positionals)
          rest_positional = RestPositional.new(
            name: rp.name&.to_s,
            element_type: RBSTypeFormatter.to_yard(rp.type, collapse_generics: @collapse_generics)
          )
        end

        rest_keywords = nil
        if (rk = func.rest_keywords)
          rest_keywords = RestKeywords.new(
            name: rk.name&.to_s,
            type: RBSTypeFormatter.to_yard(rk.type)
          )
        end

        Signature.new(
          return_type: return_type,
          param_types: param_types,
          rest_positional: rest_positional,
          rest_keywords: rest_keywords
        )
      rescue RBS::ParsingError, RBS::DefinitionBuilder::UnknownTypeNameError => e
        warn_once("Docscribe: RBS error: #{e.class}: #{e.message}")
        nil
      rescue StandardError => e
        warn_once("Docscribe: RBS integration failed (falling back to inference): #{e.class}: #{e.message}")
        nil
      end

      private

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

      def absolute_const(container)
        s = container.to_s
        s.start_with?('::') ? s : "::#{s}"
      end

      def warn_once(msg)
        return unless ENV['DOCSCRIBE_RBS_DEBUG'] == '1'
        return if defined?(@warned) && @warned

        @warned = true
        warn msg
      end
    end
  end
end
