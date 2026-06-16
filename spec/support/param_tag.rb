# frozen_string_literal: true

module ParamTag
  # Generate a YARD @param tag line matching the configured param tag style.
  #
  # @param [String] name parameter name
  # @param [String] type parameter type
  # @param [Docscribe::Config] config configuration for determining tag style (defaults to a fresh empty config)
  # @param [String] description documentation text appended to the param line (empty for struct params)
  # @param [Integer] indent number of leading spaces (defaults to 1)
  # @return [String] formatted @param tag line
  def param_tag(name, type, config: Docscribe::Config.new, description: 'Generated param description.', indent: 1)
    style = config.raw.dig('doc', 'param_tag_style') || 'type_name'

    case style
    when 'name_type'
      "##{' ' * indent}@param #{name} [#{type}]#{" #{description}" unless description.empty?}"
    when 'type_name'
      "##{' ' * indent}@param [#{type}] #{name}#{" #{description}" unless description.empty?}"
    end
  end
end
