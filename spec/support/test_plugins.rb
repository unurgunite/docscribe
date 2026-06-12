# frozen_string_literal: true

class TestCollectorPluginBase < Docscribe::Plugin::Base::CollectorPlugin
  def initialize(attrs = {})
    super()
    attrs.each { |k, v| instance_variable_set(:"@#{k}", v) }
  end
end

module TestPlugins
  module FindFirst
    def find_first(node, type)
      return nil unless node.respond_to?(:type)
      return node if node.type == type

      children = node.respond_to?(:children) ? node.children : []
      children.each do |child|
        next unless child.respond_to?(:type)

        found = find_first(child, type)
        return found if found
      end

      nil
    end
  end

  module FindFirstDef
    def find_first_def(node)
      return nil unless node.respond_to?(:type)
      return node if node.type == :def

      children = node.respond_to?(:children) ? node.children : []
      children.each do |child|
        next unless child.respond_to?(:type)

        found = find_first_def(child)
        return found if found
      end

      nil
    end
  end
end
