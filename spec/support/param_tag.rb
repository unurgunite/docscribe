# frozen_string_literal: true

module ParamTag
  # Method documentation.
  #
  # @param [Object] name Param documentation.
  # @param [Object] type Param documentation.
  # @param [Config] config Param documentation.
  # @param [String] description Param documentation.
  # @return [String]
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
