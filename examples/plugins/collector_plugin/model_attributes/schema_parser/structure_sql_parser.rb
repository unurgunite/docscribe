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

  # @!attribute [r] tables
  #   @return [Hash]
  attr_reader :tables

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

  private

  # Parse structure.sql source into a table -> column map.
  #
  # @private
  # @param [String] source
  # @return [Hash{String => Hash{String => String}}]
  def parse(source)
    tables = {}

    # Find all CREATE TABLE blocks
    source.scan(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s*\((.*?)\)\s*(?:ENGINE|DEFAULT|CHARSET|ON\s+COMMIT|;\s*$)/m) do |table_name, columns_sql|
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
    # Split by commas, but handle parentheses in types like varchar(255)
    parts = split_columns(columns_sql)

    parts.each do |part|
      part = part.strip
      next if part.empty?

      # Skip constraints: PRIMARY KEY, UNIQUE, INDEX, FOREIGN KEY, CHECK
      next if part.match?(/\A(PRIMARY\s+KEY|UNIQUE|INDEX|KEY|FOREIGN\s+KEY|CHECK|CONSTRAINT)\b/i)

      # Extract column name and type
      next unless part =~ /\A["`]?(\w+)["`]?\s+(\w+(?:\s*\(.*?\))?(?:\s+\w+\s+\w+)?)\b/i

      column_name = ::Regexp.last_match(1).downcase
      raw_type = ::Regexp.last_match(2).strip.downcase

      next if SchemaParser::SKIPPED_COLUMNS.include?(column_name)

      # Normalize type
      normalized_type = normalize_type(raw_type)
      next if normalized_type.nil?

      columns[column_name] = normalized_type
    end
  end

  # Split column definitions by comma, respecting parentheses.
  #
  # @private
  # @param [String] sql
  # @return [Array<String>]
  def split_columns(sql)
    parts = []
    depth = 0
    current = ''

    sql.each_char do |char|
      case char
      when '('
        depth += 1
        current << char
      when ')'
        depth -= 1
        current << char
      when ','
        if depth.zero?
          parts << current
          current = ''
        else
          current << char
        end
      else
        current << char
      end
    end

    parts << current unless current.strip.empty?
    parts
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
