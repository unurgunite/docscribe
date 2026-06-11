# frozen_string_literal: true

require_relative 'schema_parser'

# Parse Rails `db/structure.sql` into a table -> columns mapping.
#
# Supports PostgreSQL and MySQL SQL DDL syntax:
# - CREATE TABLE with column definitions
# - Standard SQL types: varchar, integer, boolean, timestamp, etc.
#
# @example
#   parser = StructureSqlParser.new(root: '/path/to/rails_app')
#   parser.tables
#   # => { 'users' => { 'email' => 'varchar', 'age' => 'integer' } }
class StructureSqlParser
  # SQL type -> normalized database type mapping.
  #
  # @return [Hash{String => String}]
  SQL_TYPE_MAP = {
    'boolean' => 'boolean',
    'bool' => 'boolean',
    'tinyint' => 'boolean',

    'integer' => 'integer',
    'int' => 'integer',
    'int4' => 'integer',
    'smallint' => 'smallint',
    'int2' => 'smallint',
    'bigint' => 'bigint',
    'int8' => 'bigint',
    'serial' => 'serial',
    'bigserial' => 'bigserial',

    'float' => 'float',
    'double' => 'float',
    'double precision' => 'float',
    'real' => 'float',
    'decimal' => 'decimal',
    'numeric' => 'decimal',
    'money' => 'decimal',

    'string' => 'string',
    'varchar' => 'varchar',
    'character varying' => 'varchar',
    'char' => 'char',
    'character' => 'char',
    'text' => 'text',
    'citext' => 'citext',
    'uuid' => 'uuid',

    'datetime' => 'datetime',
    'timestamp' => 'timestamp',
    'timestamptz' => 'timestamptz',
    'time' => 'time',
    'timetz' => 'timetz',
    'date' => 'date',

    'json' => 'json',
    'jsonb' => 'jsonb',
    'hstore' => 'hstore',

    'binary' => 'binary',
    'bytea' => 'binary',
    'blob' => 'binary',

    'inet' => 'inet',
    'cidr' => 'inet',
    'enum' => 'enum'
  }.freeze

  # Parse the structure.sql file and return a table -> column map.
  #
  # @param [Object] root Param documentation.
  # @return [Hash{String => Hash{String => String}}]
  def initialize(root:)
    @root = root
    @tables = nil
  end

  # @return [Hash{String => Hash{String => String}}]
  def tables
    return @tables if @tables

    path = File.join(@root, 'db', 'structure.sql')
    return @tables = {} unless File.file?(path)

    source = File.read(path)
    @tables = parse(source)
  end

  CONSTRAINT_RE = /\A(PRIMARY\s+KEY|UNIQUE|INDEX|KEY|FOREIGN\s+KEY|CHECK|CONSTRAINT)\b/i.freeze
  COLUMN_DEF_RE = /\A["`]?(\w+)["`]?\s+(\w+(?:\s*\(.*?\))?(?:\s+\w+\s+\w+)?)\b/i.freeze

  private

  # Parse structure.sql source into a table -> column map.
  #
  # @private
  # @param [String] source
  # @return [Hash{String => Hash{String => String}}]
  def parse(source)
    tables = {}

    # Find all CREATE TABLE blocks
    source.scan(
      /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s*
       \((.*?)\)\s*(?:ENGINE|DEFAULT|CHARSET|ON\s+COMMIT|;\s*$)/xm
    ) do |table_name, columns_sql|
      tables[table_name] = {}

      # Parse column definitions
      parse_columns(columns_sql, tables[table_name])
    end

    tables
  end

  # Parse column definitions from a CREATE TABLE body.
  #
  # @private
  # @param [String] columns_sql
  # @param [Hash{String => String}] columns
  # @return [Object]
  def parse_columns(columns_sql, columns)
    split_columns(columns_sql).each { |part| parse_column_part(part, columns) }
  end

  def parse_column_part(part, columns)
    part = part.strip
    return if part.empty? || part.match?(CONSTRAINT_RE)

    m = part.match(COLUMN_DEF_RE)
    return unless m

    column_name = m[1].downcase
    raw_type = m[2].strip.downcase
    return if SchemaParser::SKIPPED_COLUMNS.include?(column_name)

    normalized_type = normalize_type(raw_type)
    return if normalized_type.nil?

    columns[column_name] = normalized_type
  end

  # Split column definitions by comma, respecting parentheses.
  #
  # @private
  # @param [String] sql
  # @return [Array<String>]
  def split_columns(sql)
    parts = []
    state = { depth: 0, cur: +'' }
    sql.each_char { |c| split_char(c, parts, state) }
    parts << state[:cur] unless state[:cur].strip.empty?
    parts
  end

  def split_char(char, parts, state)
    case char
    when '(' then open_paren(state, char)
    when ')' then close_paren(state, char)
    when ',' then split_comma(char, parts, state)
    else state[:cur] << char
    end
  end

  def open_paren(state, char)
    state[:depth] += 1
    state[:cur] << char
  end

  def close_paren(state, char)
    state[:depth] -= 1
    state[:cur] << char
  end

  def split_comma(char, parts, state)
    if state[:depth].zero?
      parts << state[:cur]
      state[:cur] = +''
    else
      state[:cur] << char
    end
  end

  # Normalize a raw SQL type to our canonical type name.
  #
  # @private
  # @param [String] raw_type
  # @return [String, nil]
  def normalize_type(raw_type)
    # Handle types with parameters: varchar(255), decimal(10,2)
    base = raw_type.split('(').first.strip

    # Handle compound types: timestamp without time zone
    if base == 'timestamp'
      if raw_type.include?('without time zone')
        return 'timestamp'
      elsif raw_type.include?('with time zone')
        return 'timestamptz'
      end
    end

    # Handle double precision
    return 'double precision' if base == 'double' && raw_type.include?('precision')

    # Map to canonical type
    SchemaParser::SQL_TYPE_MAP[base]
  end
end
