# frozen_string_literal: true

require 'docscribe/types/signature'
require 'docscribe/types/rbs/type_formatter'

module Docscribe
  module Types
    module Sorbet
      class BaseProvider
        # Method documentation.
        #
        # @param [Boolean] collapse_generics Param documentation.
        # @return [Object]
        def initialize(collapse_generics: false)
          require 'rbs'
          @collapse_generics = !!collapse_generics
          @index = {}
          @warned = false
        end

        # Method documentation.
        #
        # @param [Object] container Param documentation.
        # @param [Object] scope Param documentation.
        # @param [Object] name Param documentation.
        # @return [Object]
        def signature_for(container:, scope:, name:)
          @index[[normalize_container(container), scope.to_sym, name.to_sym]]
        end

        private

        # Method documentation.
        #
        # @private
        # @param [Object] source Param documentation.
        # @param [Object] label Param documentation.
        # @raise [LoadError]
        # @raise [::RBS::BaseError]
        # @raise [SyntaxError]
        # @raise [StandardError]
        # @return [Object]
        # @return [nil] if LoadError
        # @return [nil] if ::RBS::BaseError, SyntaxError, StandardError
        def load_from_string(source, label:)
          return unless defined?(RubyVM::AbstractSyntaxTree)

          parser = ::RBS::Prototype::RBI.new
          parser.parse(source)
          index_decls(parser.decls)
        rescue LoadError
          nil
        rescue ::RBS::BaseError, SyntaxError, StandardError => e
          warn_once("Docscribe: Sorbet signature load failed for #{label}: #{e.class}: #{e.message}")
          nil
        end

        # Method documentation.
        #
        # @private
        # @param [Object] decls Param documentation.
        # @return [Object]
        def index_decls(decls)
          Array(decls).each do |decl|
            next unless decl.respond_to?(:name)
            next unless decl.respond_to?(:members)

            container = normalize_container(decl.name.to_s)

            decl.members.each do |member|
              next unless method_definition_member?(member)

              scope = member.kind == :singleton ? :class : :instance
              overload = member.overloads&.first
              next unless overload

              func = overload.method_type.type
              @index[[container, scope, member.name.to_s.to_sym]] = build_signature(func)
            end
          end
        end

        # Method documentation.
        #
        # @private
        # @param [Object] member Param documentation.
        # @return [Object]
        def method_definition_member?(member)
          defined?(::RBS::AST::Members::MethodDefinition) &&
            member.is_a?(::RBS::AST::Members::MethodDefinition)
        end

        # Method documentation.
        #
        # @private
        # @param [Object] func Param documentation.
        # @return [MethodSignature]
        def build_signature(func)
          MethodSignature.new(
            return_type: format_type(func.return_type),
            param_types: build_param_types(func),
            rest_positional: build_rest_positional(func),
            rest_keywords: build_rest_keywords(func)
          )
        end

        # Method documentation.
        #
        # @private
        # @param [Object] func Param documentation.
        # @return [Object]
        def build_param_types(func)
          param_types = {}
          add_positionals!(param_types, func.required_positionals)
          add_positionals!(param_types, func.optional_positionals)
          add_positionals!(param_types, func.trailing_positionals)

          func.required_keywords.each { |kw, p| param_types[kw.to_s] = format_type(p.type) }
          func.optional_keywords.each { |kw, p| param_types[kw.to_s] = format_type(p.type) }

          param_types
        end

        # Method documentation.
        #
        # @private
        # @param [Object] param_types Param documentation.
        # @param [Object] list Param documentation.
        # @return [Object]
        def add_positionals!(param_types, list)
          list.each do |p|
            next unless p.name

            param_types[p.name.to_s] = format_type(p.type)
          end
        end

        # Method documentation.
        #
        # @private
        # @param [Object] func Param documentation.
        # @return [RestPositional]
        def build_rest_positional(func)
          rp = func.rest_positionals
          return nil unless rp

          RestPositional.new(
            name: rp.name&.to_s,
            element_type: format_type(rp.type)
          )
        end

        # Method documentation.
        #
        # @private
        # @param [Object] func Param documentation.
        # @return [RestKeywords]
        def build_rest_keywords(func)
          rk = func.rest_keywords
          return nil unless rk

          value_type = format_type(rk.type)

          RestKeywords.new(
            name: rk.name&.to_s,
            type: "Hash<Symbol, #{value_type}>"
          )
        end

        # Method documentation.
        #
        # @private
        # @param [Object] type Param documentation.
        # @return [Object]
        def format_type(type)
          Docscribe::Types::RBS::TypeFormatter.to_yard(
            type,
            collapse_generics: @collapse_generics
          )
        end

        # Method documentation.
        #
        # @private
        # @param [Object] name Param documentation.
        # @return [Object]
        def normalize_container(name)
          name.to_s.delete_prefix('::')
        end

        # Method documentation.
        #
        # @private
        # @param [Object] msg Param documentation.
        # @return [Object]
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
