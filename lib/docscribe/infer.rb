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
  # - It aims to be correct for common Ruby patterns and safe for unknown cases.
  # - When inference is uncertain, it returns "Object".
  #
  # RBS-based typing (when enabled) is applied in the doc builder, not here.
  module Infer
    class << self
      # Infer exception class names that the method may raise.
      #
      # @param node [Parser::AST::Node] a method node (`:def` or `:defs`)
      # @return [Array<String>] unique exception class names
      def infer_raises_from_node(node)
        Raises.infer_raises_from_node(node)
      end

      # Infer parameter type from name and default value string.
      #
      # @param name [String]
      # @param default_str [String, nil]
      # @return [String]
      def infer_param_type(name, default_str)
        Params.infer_param_type(name, default_str)
      end

      # Parse a Ruby expression from a string into an AST node.
      #
      # @param src [String, nil]
      # @return [Parser::AST::Node, nil]
      def parse_expr(src)
        Params.parse_expr(src)
      end

      # Infer return type of method from its source text.
      #
      # @param method_source [String, nil]
      # @return [String]
      def infer_return_type(method_source)
        Returns.infer_return_type(method_source)
      end

      # Infer return type from an already-parsed method node.
      #
      # @param node [Parser::AST::Node] `:def` or `:defs`
      # @return [String]
      def infer_return_type_from_node(node)
        Returns.infer_return_type_from_node(node)
      end

      # Compute normal return type and rescue-conditional return types for a method.
      #
      # @param node [Parser::AST::Node]
      # @return [Hash{Symbol=>Object}] `{ normal: String, rescues: Array<[Array<String>, String]> }`
      def returns_spec_from_node(node)
        Returns.returns_spec_from_node(node)
      end

      # Infer the type of the "last expression" of a Ruby AST node.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [String, nil]
      def last_expr_type(node)
        Returns.last_expr_type(node)
      end

      # Convert a constant-like AST node into a fully qualified name.
      #
      # @param n [Parser::AST::Node, nil]
      # @return [String, nil]
      def const_full_name(n)
        Names.const_full_name(n)
      end

      # Infer a type name from a literal node.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [String]
      def type_from_literal(node)
        Literals.type_from_literal(node)
      end

      # Unify two inferred types conservatively.
      #
      # @param a [String, nil]
      # @param b [String, nil]
      # @return [String]
      def unify_types(a, b)
        Returns.unify_types(a, b)
      end
    end
  end
end
