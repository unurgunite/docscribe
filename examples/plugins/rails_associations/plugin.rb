# frozen_string_literal: true

require 'docscribe/plugin'
require 'docscribe/infer/ast_walk'

module DocscribePlugins
  # Generates YARD documentation for ActiveRecord association macros.
  #
  # Supports:
  # - belongs_to
  # - has_one
  # - has_many
  # - has_and_belongs_to_many
  #
  # @example Registration
  #   require 'examples/plugins/rails_associations/plugin'
  #   Docscribe::Plugin::Registry.register(DocscribePlugins::RailsAssociations.new)
  #
  # @example belongs_to
  #   # @!attribute [r] requestable
  #   #   Associated Requestable object.
  #   #
  #   #   @return [ApplicationRecord]
  #   belongs_to :requestable, polymorphic: true, optional: true
  #
  # @example has_many
  #   # @!attribute [r] songs
  #   #   Returns the associated songs.
  #   #
  #   #   @return [Array<Song>]
  #   has_many :songs, dependent: :destroy
  class RailsAssociations < Docscribe::Plugin::Base::CollectorPlugin
    ASSOCIATION_METHODS = %i[belongs_to has_one has_many has_and_belongs_to_many].freeze

    # Walk the AST and return doc insertion targets for association macros.
    #
    # @param [Parser::AST::Node] ast
    # @param [Parser::Source::Buffer] _buffer
    # @return [Array<Hash>]
    def collect(ast, _buffer)
      results = []

      Docscribe::Infer::ASTWalk.walk(ast) do |node|
        next unless association_node?(node)

        _recv, meth, name_node, *option_nodes = *node
        next unless name_node&.type == :sym

        assoc_name = name_node.children.first
        options    = extract_options(option_nodes)
        indent     = extract_indent(node)

        doc = build_doc(meth, assoc_name, options, indent)
        results << { anchor_node: node, doc: doc }
      end

      results
    end

    private

    # Whether a node is a recognized association macro call.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @return [Boolean]
    def association_node?(node)
      return false unless node.type == :send

      recv, meth, *_args = *node
      recv.nil? && ASSOCIATION_METHODS.include?(meth)
    end

    # Extract option key-value pairs from the trailing Hash argument.
    #
    # @private
    # @param [Array<Parser::AST::Node>] option_nodes
    # @return [Hash{Symbol => Object}]
    def extract_options(option_nodes)
      hash_node = option_nodes.find { |n| n.is_a?(Parser::AST::Node) && n.type == :hash }
      return {} unless hash_node

      hash_node.children.each_with_object({}) do |pair, opts|
        next unless pair.type == :pair

        key_node, val_node = *pair
        key = key_node.children.first if key_node.type == :sym
        next unless key

        opts[key] = extract_value(val_node)
      end
    end

    # Extract a primitive value from an AST node.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @return [Object, nil]
    def extract_value(node)
      case node.type
      when :sym, :str then node.children.first
      when true       then true
      when false      then false
      when :nil       then nil
      else node.type
      end
    end

    # Extract source indentation from a node.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @raise [StandardError]
    # @return [String]
    def extract_indent(node)
      line = node.loc.expression.source_line
      line[/\A[ \t]*/] || ''
    rescue StandardError
      ''
    end

    # Build a complete doc block string for one association.
    #
    # @private
    # @param [Symbol] meth association method name
    # @param [Symbol] assoc_name association name
    # @param [Hash] options parsed options
    # @param [String] indent source indentation
    # @return [String]
    def build_doc(meth, assoc_name, options, indent)
      return_type = resolve_return_type(meth, assoc_name, options)
      description = build_description(meth, assoc_name, options)

      lines = []
      lines << "#{indent}# @!attribute [r] #{assoc_name}"
      lines << "#{indent}#   #{description}"
      lines << "#{indent}#"
      lines << "#{indent}#   @return [#{return_type}]"
      lines << "#{indent}#"

      lines.map { |l| "#{l}\n" }.join
    end

    # Resolve the YARD return type for an association.
    #
    # @private
    # @param [Symbol] meth
    # @param [Symbol] assoc_name
    # @param [Hash] options
    # @return [String]
    def resolve_return_type(meth, assoc_name, options)
      case meth
      when :belongs_to, :has_one
        if options[:polymorphic]
          'ApplicationRecord'
        else
          class_name_from_options(options) || camelize(assoc_name)
        end
      when :has_many, :has_and_belongs_to_many
        inner = class_name_from_options(options) || camelize(singular(assoc_name))
        "Array<#{inner}>"
      end
    end

    # Build a one-line description for an association.
    #
    # @private
    # @param [Symbol] meth
    # @param [Symbol] assoc_name
    # @param [Hash] options
    # @return [String]
    def build_description(meth, assoc_name, options)
      case meth
      when :belongs_to
        polymorphic = options[:polymorphic] ? ' (polymorphic)' : ''
        "Associated #{assoc_name}#{polymorphic} object."
      when :has_one
        "Associated #{assoc_name} object."
      when :has_many
        "Returns the associated #{assoc_name}."
      when :has_and_belongs_to_many
        "Returns the associated #{assoc_name} (HABTM)."
      end
    end

    # Extract class_name: option if present.
    #
    # @private
    # @param [Hash] options
    # @return [String, nil]
    def class_name_from_options(options)
      options[:class_name]&.to_s
    end

    # CamelCase a symbol.
    #
    # @private
    # @param [Symbol, String] name
    # @return [String]
    def camelize(name)
      name.to_s.split('_').map(&:capitalize).join
    end

    # Naive singularize: strips trailing 's'.
    #
    # @private
    # @param [Symbol, String] name
    # @return [String]
    def singular(name)
      str = name.to_s
      str.end_with?('s') ? str[0..-2] : str
    end
  end
end
