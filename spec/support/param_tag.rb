# frozen_string_literal: true

module ParamTag
  # Generate a YARD @param tag line matching the configured param tag style.
  #
  # @param [String] name parameter name
  # @param [String] type parameter type
  # @param [Docscribe::Config] config configuration for determining tag style (defaults to a fresh empty config)
  # @param [String] description documentation text appended to the param line
  # @param [Integer] space_size number of leading spaces (defaults to 1)
  # @param [Boolean] struct whether this is a struct param (omits description when true)
  # @return [String] formatted @param tag line
  def param_tag(name, type, config: Docscribe::Config.new, description: 'Param documentation.', space_size: 1,
                struct: false)
    style = config.raw.dig('doc', 'param_tag_style') || 'type_name'

    desc = struct ? '' : " #{description}"
    case style
    when 'name_type'
      "##{' ' * space_size}@param #{name} [#{type}]#{desc}"
    when 'type_name'
      "##{' ' * space_size}@param [#{type}] #{name}#{desc}"
    end
  end
end
