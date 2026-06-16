# frozen_string_literal: true

# NOTE: parser/base references Racc::Parser in some environments, so require runtime first.
require 'racc/parser'
require 'ast'
require 'parser/ast/node'
require 'parser/source/buffer'
require 'parser/base'

require 'docscribe/parsing'

require_relative 'infer/constants'
require_relative 'infer/ast_walk'
require_relative 'infer/names'
require_relative 'infer/literals'
require_relative 'infer/params'
require_relative 'infer/returns'
require_relative 'infer/raises'

module Docscribe
  # Best-effort inference utilities used to generate YARD tags.
  #
  # This module is intentionally heuristic:
  # - it aims to be useful for common Ruby patterns
  # - it prefers safe fallback behavior when uncertain
  # - when inference cannot be specific, it falls back to `Object`
  #
  # External signature sources such as RBS and Sorbet are applied later in the
  # doc builder and can override these inferred types.
  module Infer
    class << self
      # Infer exception classes raised or rescued within an AST node.
      #
      # @param [Parser::AST::Node] node constant AST node to resolve
      # @return [Array<String>]
      def infer_raises_from_node(node)
        Raises.infer_raises_from_node(node)
      end

      # Infer a parameter type from its internal name form and optional default
      # expression.
      #
      # The internal parameter name may include:
      # - `*` for rest args
      # - `**` for keyword rest args
      # - `&` for block args
      # - trailing `:` for keyword args
      #
      # @param [String] name internal parameter name representation
      # @param [String?] default_str source for the default expression
      # @param [String] fallback_type Param documentation.
      # @param [Boolean] treat_options_keyword_as_hash Param documentation.
      # @return [String]
      def infer_param_type(name, default_str, fallback_type: FALLBACK_TYPE, treat_options_keyword_as_hash: true)
        Params.infer_param_type(
          name,
          default_str,
          fallback_type: fallback_type,
          treat_options_keyword_as_hash: treat_options_keyword_as_hash
        )
      end

      # Parse a standalone expression source string for inference helpers.
      #
      # @param [String?] src Param documentation.
      # @return [Parser::AST::Node, nil]
      def parse_expr(src)
        Params.parse_expr(src)
      end

      # Infer a return type from full method source.
      #
      # @param [String?] method_source Param documentation.
      # @return [String]
      def infer_return_type(method_source)
        Returns.infer_return_type(method_source)
      end

      # Infer a return type from an already parsed `:def` / `:defs` node.
      #
      # @param [Parser::AST::Node] node constant AST node to resolve
      # @return [String]
      def infer_return_type_from_node(node)
        Returns.infer_return_type_from_node(node)
      end

      # Return structured normal/rescue return information for a method node.
      #
      # Result shape:
      # - `:normal` => the normal return type
      # - `:rescues` => rescue-branch conditional return info
      #
      # @param [Parser::AST::Node] node constant AST node to resolve
      # @param [String] fallback_type Param documentation.
      # @param [Boolean] nil_as_optional Param documentation.
      # @param [Object?] core_rbs_provider core RBS type lookup provider
      # @param [Hash<String, String>?] param_types parameter name -> type map
      # @return [Object]
      def returns_spec_from_node(node, fallback_type: FALLBACK_TYPE, nil_as_optional: true, core_rbs_provider: nil,
                                 param_types: nil)
        Returns.returns_spec_from_node(
          node,
          fallback_type: fallback_type,
          nil_as_optional: nil_as_optional,
          core_rbs_provider: core_rbs_provider,
          param_types: param_types
        )
      end

      # Infer the type of the last expression in an AST node.
      #
      # @param [Parser::AST::Node, nil] node constant AST node to resolve
      # @param [String] fallback_type Param documentation.
      # @param [Boolean] nil_as_optional Param documentation.
      # @return [String, nil]
      def last_expr_type(node, fallback_type: FALLBACK_TYPE, nil_as_optional: true)
        Returns.last_expr_type(
          node,
          fallback_type: fallback_type,
          nil_as_optional: nil_as_optional
        )
      end

      # Convert a constant AST node into its fully qualified name.
      #
      # @param [Parser::AST::Node, nil] node constant AST node to resolve
      # @return [String, nil]
      def const_full_name(node)
        Names.const_full_name(node)
      end

      # Infer a YARD-ish type string from a literal AST node.
      #
      # @param [Parser::AST::Node, nil] node constant AST node to resolve
      # @param [String] fallback_type Param documentation.
      # @return [String]
      def type_from_literal(node, fallback_type: FALLBACK_TYPE)
        Literals.type_from_literal(node, fallback_type: fallback_type)
      end

      # Unify two inferred type strings conservatively.
      #
      # @param [String, nil] type_a Param documentation.
      # @param [String, nil] type_b Param documentation.
      # @param [String] fallback_type Param documentation.
      # @param [Boolean] nil_as_optional Param documentation.
      # @return [String]
      def unify_types(type_a, type_b, fallback_type: FALLBACK_TYPE, nil_as_optional: true)
        Returns.unify_types(
          type_a,
          type_b,
          fallback_type: fallback_type,
          nil_as_optional: nil_as_optional
        )
      end
    end
  end
end
