# frozen_string_literal: true

require 'docscribe/plugin'
require 'docscribe/infer/ast_walk'
require_relative 'schema_parser/schema_parser'

module DocscribePlugins
  # ModelAttributes plugin — generates yard documentation for model methods
  # by consulting a database schema parser for column types.
  #
  # Instead of just generating `@!attribute` blocks, this plugin analyzes
  # method bodies and generates accurate `@return` / `@param` types based on
  # the underlying column types from `db/schema.rb` or `db/structure.sql`.
  #
  # @example Generated output for a model
  #   class User < ApplicationRecord
  #     # @return [Boolean]
  #     def admin?
  #       is_admin
  #     end
  #
  #     # @return [Boolean]
  #     def age_restriction?
  #       age < 21
  #     end
  #
  #     # @return [String]
  #     def fullname
  #       name + surname
  #     end
  #   end
  #
  # @example Registration
  #   require 'examples/plugins/collector_plugin/model_attributes/plugin'
  #   Docscribe::Plugin::Registry.register(DocscribePlugins::ModelAttributes.new)
  class ModelAttributes < Docscribe::Plugin::Base::CollectorPlugin
    LITERAL_TYPES = {
      str: 'String',
      dstr: 'String',
      int: 'Integer',
      float: 'Integer',
      nil: 'nil',
      array: 'Array',
      hash: 'Hash',
      regexp: 'Regexp'
    }.freeze

    STRING_RETURN_METHODS = %i[
      upcase downcase capitalize capitalize_first
      strip lstrip rstrip
      trim gsub sub gsub! sub!
      truncate
      concat append +
      split chars each_char each_line
      include? start_with? end_with?
      match scan find_index
      empty? present? blank?
      to_s to_str
      prepend reverse reverse!
      swapcase swapcase!
      tr tr_s tr_t tr_u
      slice slice!
      chars bytes
    ].freeze

    STRING_INTEGER_RETURN_METHODS = %i[length size count].freeze

    INTEGER_BOOLEAN_METHODS = %i[
      zero? one? positive? negative?
      even? odd? finite?
    ].freeze

    INTEGER_ARITHMETIC_METHODS = %i[+ - * / % **].freeze

    INTEGER_RETURN_METHODS = %i[
      floor ceil round trunc
      abs <=>
    ].freeze

    STRING_METHODS = %i[
      upcase downcase capitalize
      strip lstrip rstrip
      gsub sub
      truncate
      concat append +
      include? start_with? end_with?
      match scan
      empty? present? blank?
      to_s to_str
      length size count
      reverse
    ].freeze

    INTEGER_METHODS = %i[
      zero? one? positive? negative?
      even? odd?
      floor ceil round
      abs
      + - * / % **
    ].freeze

    # @!attribute [r] root
    #   @return [String] Rails application root directory
    attr_reader :root

    # @!attribute [r] schema_tables
    #   @return [Hash{String => Hash{String => String}}] table -> column -> db_type
    attr_reader :schema_tables

    # @!attribute [r] yard_type_map
    #   @return [Hash{String => String}] db_type -> YARD type
    attr_reader :yard_type_map

    # Walk the AST and return doc insertion targets for model methods.
    #
    # @param [Parser::AST::Node] ast
    # @param [Parser::Source::Buffer] _buffer Param documentation.
    # @return [Array<Hash>]
    def collect(ast, _buffer)
      return [] unless active_record_model?(ast)

      tables = load_schema!
      return [] if tables.empty?

      build_method_docs(ast, tables)
    end

    private

    # Create a new schema attribute collector.
    #
    # @private
    # @param [String] root
    # @return [self]
    def initialize(root: Dir.pwd)
      super()
      @root = root
      @schema_tables = nil
      @yard_type_map = SchemaParser::TYPE_MAP
    end

    # Whether the AST defines an ActiveRecord model class.
    #
    # @private
    # @param [Parser::AST::Node] ast
    # @return [Boolean]
    def active_record_model?(ast)
      Docscribe::Infer::ASTWalk.walk(ast) do |node|
        next unless node.type == :class

        _name, parent = *node
        next unless parent

        return true if active_record_parent?(parent)
      end

      false
    end

    def active_record_parent?(parent)
      application_record_parent?(parent) ||
        active_record_base_parent?(parent)
    end

    def application_record_parent?(parent)
      parent.type == :const &&
        parent.children[1] == :ApplicationRecord
    end

    def active_record_base_parent?(parent)
      parent.type == :const &&
        parent.children[0]&.type == :const &&
        parent.children[0].children[1] == :ActiveRecord &&
        parent.children[1] == :Base
    end

    # Extract the model class name from the AST.
    #
    # @private
    # @param [Parser::AST::Node] ast
    # @return [String, nil]
    def extract_model_name(ast)
      Docscribe::Infer::ASTWalk.walk(ast) do |node|
        if node.type == :class
          name_node = node.children[0]
          return resolve_const_name(name_node) if name_node
        end
      end
      nil
    end

    # Load schema.rb or structure.sql and return table columns.
    #
    # @private
    # @raise [StandardError]
    # @return [Hash{String => Hash{String => String}}]
    def load_schema!
      return @schema_tables if @schema_tables

      @schema_tables = SchemaParser.resolve_tables(root: @root)
    rescue StandardError => e
      warn "Docscribe ModelAttributes: failed to load schema: #{e.message}" if ENV['DOCSCRIBE_DEBUG'] == '1'
      @schema_tables = {}
    end

    # Build doc blocks for methods in all model classes.
    #
    # Each class gets its own table's column mapping.
    #
    # @private
    # @param [Parser::AST::Node] ast
    # @param [Hash{String => Hash{String => String}}] tables
    # @return [Array<Hash>]
    def build_method_docs(ast, tables)
      results = []

      Docscribe::Infer::ASTWalk.walk(ast) do |node|
        collect_class_method_docs(node, tables, results)
      end

      results
    end

    def collect_class_method_docs(node, tables, results)
      return unless node.type == :class

      columns = model_columns_for(node, tables)
      return unless columns

      method_nodes_for(node).each do |meth_node|
        doc = build_method_doc(meth_node, columns)
        results << doc if doc
      end
    end

    def model_columns_for(node, tables)
      model_name = resolve_const_name(node.children[0])
      return unless model_name

      tables[model_name_to_table_name(model_name)]
    end

    # Convert a model class name to a table name.
    #
    # @private
    # @param [String] model_name
    # @return [String]
    def model_name_to_table_name(model_name)
      parts = model_name.split('::')
      table = parts.map do |p|
        p.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .downcase
      end.join('_')
      pluralize(table)
    end

    # Simple English pluralization (handles most common cases).
    #
    # @private
    # @param [String] word
    # @return [String]
    def pluralize(word)
      return word if word.end_with?('s', 'x', 'z', 'ch', 'sh')
      return "#{word[0..-2]}ies" if word.match?(/[^aeiou]y\Z/)
      return "#{word}es" if word.end_with?('es', 'us') || word.match?(/[^aeiou]o\Z/)
      return "#{word[0..-3]}ves" if word.end_with?('fe')
      return "#{word[0..-2]}ves" if word.end_with?('f')

      "#{word}s"
    end

    def method_nodes_for(node)
      _name, _parent, body = *node
      return [] unless body

      stmts = body.type == :begin ? body.children : [body]
      stmts.select { |stmt| %i[def defs].include?(stmt.type) }
    end

    def build_method_doc(meth_node, columns)
      meth_name = method_name(meth_node)
      return if reserved_method?(meth_name.to_s)

      inferred_type = infer_method_return_type(meth_node, columns)
      return unless inferred_type

      {
        anchor_node: meth_node,
        method_override: {
          return_type: inferred_type
        }
      }
    end

    def method_name(node)
      case node.type
      when :def
        node.children[0]
      when :defs
        node.children[1]
      end
    end

    # Check if a method name should be skipped.
    #
    # @private
    # @param [String] name
    # @return [Boolean]
    def reserved_method?(name)
      %w[
        id to_yaml to_json to_xml
        persisted? new_record?
        will_save_change_to? saved_change_to?
      ].include?(name)
    end

    # Infer the return type for a method based on column types.
    #
    # @private
    # @param [Parser::AST::Node] meth_node
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_method_return_type(meth_node, columns)
      body = method_body_node(meth_node)
      return unless body

      last_expr = extract_last_expression(body)
      return unless last_expr

      infer_type_from_node(last_expr, columns)
    end

    def method_body_node(meth_node)
      case meth_node.type
      when :def
        meth_node.children[2]
      when :defs
        meth_node.children[3]
      end
    end

    # Extract the last expression from a body node.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @return [Parser::AST::Node, nil]
    def extract_last_expression(node)
      return node unless node.type == :begin

      children = node.children
      children.empty? ? nil : children.last
    end

    # Infer the YARD type from a node, using column types for attribute references.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_type_from_node(node, columns)
      return infer_send_type(node, columns) if node.type == :send
      return infer_variable_type(node, columns) if variable_node?(node)
      return resolve_const_name(node) if node.type == :const

      literal_type(node) || 'Object'
    end

    # Resolve a possibly-namespaced constant name to a string.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @return [String, nil]
    def resolve_const_name(node)
      return nil unless node && node.type == :const

      name = node.children[1]&.to_s
      return name if node.children[0].nil?

      prefix = resolve_const_name(node.children[0])
      return name unless prefix

      "#{prefix}::#{name}"
    end

    def variable_node?(node)
      %i[lvar ivasgn ivar].include?(node.type)
    end

    def literal_type(node)
      return 'Boolean' if [true, false].include?(node.type)

      LITERAL_TYPES[node.type]
    end

    # Infer return type for a send node (method call).
    #
    # @private
    # @param [Parser::AST::Node] node
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_send_type(node, columns)
      _recv, meth, *args = *node

      # Simple attribute access: is_admin, name, email
      if node.children.size <= 2 && !node.children[0]
        # Method call with no receiver — likely an attribute reader
        return column_yard_type(meth.to_s, columns)
      end

      # Comparison operators: age < 21, name != 'admin'
      return infer_comparison_type(meth, args, columns) if comparison_method?(meth)

      # String methods: name + surname, name.upcase, name.strip
      return infer_string_method_type(meth, args, columns) if string_method?(meth)

      # Integer methods: age + 1, age.zero?
      return infer_integer_method_type(meth, args, columns) if integer_method?(meth)

      'Object'
    end

    # Infer return type for a variable reference.
    #
    # @private
    # @param [Parser::AST::Node] node
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_variable_type(node, columns)
      column_yard_type(variable_column_name(node), columns)
    end

    def variable_column_name(node)
      case node.type
      when :lvar
        node.children[0].to_s
      when :ivar
        node.children[0].to_s.sub(/^@/, '')
      when :ivasgn
        node.children[0].to_s.sub(/=$/, '')
      end
    end

    # Infer return type for comparison operators.
    #
    # @private
    # @param [Symbol] meth
    # @param [Array<Parser::AST::Node>] args
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_comparison_type(meth, args, columns)
      return 'Boolean' if %i[< <= > >= <=> == === != =~ !~].include?(meth)

      # Handle two-operand comparisons where one arg is an attribute
      return column_yard_type(args.first, columns) if args.size == 1

      'Object'
    end

    # Infer return type for string manipulation methods.
    #
    # @private
    # @param [Symbol] meth
    # @param [Array<Parser::AST::Node>] args
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def infer_string_method_type(meth, args, columns)
      return 'String' if STRING_RETURN_METHODS.include?(meth)
      return infer_type_from_node(args.first, columns) if meth == :+
      return 'Integer' if STRING_INTEGER_RETURN_METHODS.include?(meth)

      'Object'
    end

    # Infer return type for integer manipulation methods.
    #
    # @private
    # @param [Symbol] meth
    # @param [Array<Parser::AST::Node>] _args
    # @param [Hash{String => String}] _columns
    # @return [String, nil]
    def infer_integer_method_type(meth, _args, _columns)
      return 'Boolean' if INTEGER_BOOLEAN_METHODS.include?(meth)
      return 'Integer' if INTEGER_ARITHMETIC_METHODS.include?(meth)
      return 'Integer' if INTEGER_RETURN_METHODS.include?(meth)

      'Object'
    end

    # Check if a method name is a comparison operator.
    #
    # @private
    # @param [Symbol] meth
    # @return [Boolean]
    def comparison_method?(meth)
      %i[< <= > >= <=> == === != =~ !~].include?(meth)
    end

    # Check if a method name is a string manipulation method.
    #
    # @private
    # @param [Symbol] meth
    # @return [Boolean]
    def string_method?(meth)
      STRING_METHODS.include?(meth)
    end

    # Check if a method name is an integer manipulation method.
    #
    # @private
    # @param [Symbol] meth
    # @return [Boolean]
    def integer_method?(meth)
      %i[
        zero? one? positive? negative?
        even? odd?
        floor ceil round
        abs
        + - * / % **
      ].include?(meth)
    end

    # Get the YARD type for a column by name.
    #
    # @private
    # @param [String, Symbol, Parser::AST::Node, nil] name
    # @param [Hash{String => String}] columns
    # @return [String, nil]
    def column_yard_type(name, columns)
      return nil unless name

      col_name = name.to_s
      return nil if SchemaParser::SKIPPED_COLUMNS.include?(col_name)

      db_type = columns[col_name]
      return nil unless db_type

      SchemaParser.yard_type_for(db_type)
    end
  end
end
