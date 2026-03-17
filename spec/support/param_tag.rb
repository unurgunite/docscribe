# frozen_string_literal: true

module ParamTag
  # +ParamTag#param_tag+ -> String
  #
  # Method documentation.
  #
  # @param [Object] name Param documentation.
  # @param [Object] type Param documentation.
  # @param [Config] config Param documentation.
  # @param [String] description Param documentation.
  # @return [String]
  def param_tag(name, type, config: Docscribe::Config.new, description: 'Param documentation.')
    style = config.raw.dig('doc', 'param_tag_style') || 'type_name'

    case style
    when 'name_type'
      "# @param #{name} [#{type}] #{description}"
    when 'type_name'
      "# @param [#{type}] #{name} #{description}"
    end
  end
end
