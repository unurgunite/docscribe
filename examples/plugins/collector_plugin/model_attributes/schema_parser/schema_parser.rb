# frozen_string_literal: true

require_relative 'schema_rb_parser'
require_relative 'structure_sql_parser'

# SchemaParser — standalone parser for Rails database schemas.
#
# Designed as a library that can be used independently of docscribe.
# Provides a unified interface over two formats:
# - `db/schema.rb` (Ruby DSL)
# - `db/structure.sql` (SQL DDL)
#
# @example Usage
#   require 'examples/plugins/schema_parser'
#
#   # For schema.rb
#   schema = SchemaParser::SchemaRbParser.new(root: '/path/to/rails_app').tables
#   # => { 'users' => { 'email' => 'string', 'age' => 'integer' } }
#
#   # For structure.sql
#   structure = SchemaParser::StructureSqlParser.new(root: '/path/to/rails_app').tables
#   # => { 'users' => { 'email' => 'character varying', 'age' => 'integer' } }
#
#   # Unified interface
#   tables = SchemaParser.resolve_tables(root: '/path/to/rails_app')
#
#   # Type mapping for yard/doc purposes
#   yard_types = SchemaParser.type_map
#   # => { 'string' => 'String', 'integer' => 'Integer', ... }
module SchemaParser
  # Common column information struct.
  #
  # @!attribute [r] name
  #   @return [String] column name
  # @!attribute [r] type
  #   @return [String] raw database type
  # @!attribute [r] sql_type
  #   @return [String, nil] full SQL type (e.g. "character varying(255)")
  # @!attribute [r] options
  #   @return [Hash] additional metadata (null, default, index, etc.)
  Column = Struct.new(:name, :type, :sql_type, :options, keyword_init: true)

  # Unified column info with YARD type resolution.
  #
  # @!attribute [r] name
  #   @return [String] column name
  # @!attribute [r] yard_type
  #   @return [String] YARD type for documentation
  # @!attribute [r] raw_type
  #   @return [String] raw database type
  # @!attribute [r] nullable
  #   @return [Boolean]
  # @!attribute [r] default
  #   @return [Object, nil]
  ColumnWithYard = Struct.new(:name, :yard_type, :raw_type, :nullable, :default, keyword_init: true)

  # Database type → YARD type mapping for documentation.
  #
  # @return [Hash{String => String}]
  TYPE_MAP = {
    'boolean' => 'Boolean',
    'integer' => 'Integer',
    'bigint' => 'Integer',
    'smallint' => 'Integer',
    'float' => 'Float',
    'double' => 'Float',
    'decimal' => 'BigDecimal',
    'numeric' => 'BigDecimal',
    'money' => 'BigDecimal',
    'string' => 'String',
    'varchar' => 'String',
    'text' => 'String',
    'citext' => 'String',
    'char' => 'String',
    'character' => 'String',
    'binary' => 'String',
    'blob' => 'String',
    'bytea' => 'String',
    'datetime' => 'Time',
    'timestamp' => 'Time',
    'timestamptz' => 'Time',
    'date' => 'Date',
    'time' => 'Time',
    'timetz' => 'Time',
    'json' => 'Hash',
    'jsonb' => 'Hash',
    'inet' => 'IPAddr',
    'uuid' => 'String',
    'hstore' => 'Hash',
    'enum' => 'String',
    'serial' => 'Integer',
    'bigserial' => 'Integer',
    'oid' => 'Integer',
    'regclass' => 'String',
    'regtype' => 'String',
    'xml' => 'String',
    'point' => 'String',
    'line' => 'String',
    'lseg' => 'String',
    'box' => 'String',
    'circle' => 'String',
    'polygon' => 'String',
    'geometry' => 'String',
    'geometry_collection' => 'String',
    'multipoint' => 'String',
    'multilinestring' => 'String',
    'multipolygon' => 'String'
  }.freeze

  # Standard Rails columns skipped by the plugin.
  #
  # @return [Set<String>]
  SKIPPED_COLUMNS = %w[id created_at updated_at deleted_at].to_set.freeze

  # Resolve tables from the Rails application root directory.
  #
  # Prefers `db/schema.rb` if present; falls back to `db/structure.sql`.
  #
  # @param [String] root
  # @return [Hash{String => Hash{String => String}}]
  def self.resolve_tables(root:)
    schema_path = File.join(root, 'db', 'schema.rb')
    structure_path = File.join(root, 'db', 'structure.sql')

    if File.file?(schema_path)
      SchemaRbParser.new(root: root).tables
    elsif File.file?(structure_path)
      StructureSqlParser.new(root: root).tables
    else
      {}
    end
  end

  # Get YARD type for a database column type.
  #
  # @param [String] db_type
  # @return [String]
  def self.yard_type_for(db_type)
    base = db_type.split('(').first.strip.downcase
    TYPE_MAP.fetch(base, 'Object')
  end

  # Parse a schema.rb file and return table columns.
  #
  # @param [String] root
  # @return [Hash{String => Hash{String => String}}]
  def self.parse_schema_rb(root:)
    SchemaRbParser.new(root: root).tables
  end

  # Parse a structure.sql file and return table columns.
  #
  # @param [String] root
  # @return [Hash{String => Hash{String => String}}]
  def self.parse_structure_sql(root:)
    StructureSqlParser.new(root: root).tables
  end
end
