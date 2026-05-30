# frozen_string_literal: true

require_relative 'schema_parser'

# Parse Rails `db/schema.rb` into a table → columns mapping.
#
# Supports:
# - create_table blocks
# - add_column, add_index, create_table (standalone)
# - Standard Rails column types: string, integer, bigint, boolean, etc.
#
# @example
#   parser = SchemaRbParser.new(root: '/path/to/rails_app')
#   parser.tables
#   # => { 'users' => { 'email' => 'string', 'age' => 'integer' } }
class SchemaRbParser
  # Column types recognized in schema.rb.
  #
  # @return [Hash{String => String}]
  COLUMN_TYPES = {
    'boolean' => 'boolean',
    'integer' => 'integer',
    'bigint' => 'bigint',
    'smallint' => 'smallint',
    'float' => 'float',
    'decimal' => 'decimal',
    'string' => 'string',
    'text' => 'text',
    'binary' => 'binary',
    'datetime' => 'datetime',
    'time' => 'time',
    'date' => 'date',
    'timestamp' => 'datetime',
    'timestamptz' => 'datetime',
    'json' => 'json',
    'jsonb' => 'jsonb',
    'inet' => 'inet',
    'uuid' => 'uuid',
    'citext' => 'citext',
    'hstore' => 'hstore',
    'serial' => 'serial',
    'bigserial' => 'bigserial',
    'oid' => 'oid',
    'primary_key' => 'primary_key',
    'references' => 'references',
    'polymorphic' => 'polymorphic',
    'unsigned_integer' => 'integer',
    'unsigned_bigint' => 'bigint'
  }.freeze

  # Standard Rails columns that are documented by convention and skipped.
  #
  # @return [Set<String>]
  SKIPPED_COLUMNS = %w[id created_at updated_at deleted_at].to_set.freeze

  # Parse the schema.rb file and return a table → column map.
  #
  # @return [Hash{String => Hash{String => String}}]
  def tables
    return @tables if @tables

    path = File.join(@root, 'db', 'schema.rb')
    return @tables = {} unless File.file?(path)

    source = File.read(path)
    @tables = parse(source)
  end

  private

  # @param [String] root
  def initialize(root:)
    @root = root
    @tables = nil
  end

  # Parse schema.rb source into a table → column map.
  #
  # @param [String] source
  # @return [Hash{String => Hash{String => String}}]
  def parse(source)
    tables = {}
    current_table = nil

    source.each_line do |line|
      # Match create_table "table_name" or create_table :table_name
      if (m = line.match(/\A\s*create_table\s+["'](\w+)["']/))
        current_table = m[1]
        tables[current_table] ||= {}
      elsif (m = line.match(/\A\s*t\.(\w+)\s+["'](\w+)["']/))
        col_type = m[1]
        col_name = m[2]
        next if SKIPPED_COLUMNS.include?(col_name)
        next unless COLUMN_TYPES.key?(col_type)

        tables[current_table][col_name] = COLUMN_TYPES[col_type]
      elsif (m = line.match(/\A\s*add_column\s+["'](\w+)["']\s+["'](\w+)["']\s+["'](\w+)["']/)) ||
            (m = line.match(/\A\s*add_column\s+["'](\w+)["']\s+["'](\w+)["']\s+(\w+)/))
        table_name = m[1]
        col_name = m[2]
        col_type = m[3]
        next unless COLUMN_TYPES.key?(col_type)

        tables[table_name] ||= {}
        tables[table_name][col_name] = COLUMN_TYPES[col_type]
      end
    end

    tables
  end
end
