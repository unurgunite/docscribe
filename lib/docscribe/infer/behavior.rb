# frozen_string_literal: true

module Docscribe
  module Infer
    module Behavior
      MUTATING_METHODS = %i[<< push pop delete merge update write save create destroy
                             insert update_all delete_all].freeze

      class << self
        def analyze(body, method_name)
          result = {
            predicate: method_name&.to_s&.end_with?('?') || false,
            bang: method_name&.to_s&.end_with?('!') || false,
            has_side_effects: false,
            delegates: nil,
            returns_self: false,
            returns_boolean: false
          }

          return result unless body.is_a?(Parser::AST::Node)

          analyze_body(body, result)
          result
        end

        def infer_description(analysis, method_name)
          return nil unless analysis[:has_side_effects] || analysis[:predicate]

          if analysis[:predicate]
            "Returns true if the condition is met, false otherwise"
          elsif analysis[:returns_self]
            "Returns self to allow method chaining"
          elsif analysis[:has_side_effects]
            nil
          end
        end

        private

        def analyze_body(node, result)
          case node.type
          when :ivasgn, :ivar
            result[:has_side_effects] = true
          when :send
            analyze_send(node, result)
          when :self
            result[:returns_self] = true if result[:returns_self]
          end

          node.children.each do |child|
            analyze_body(child, result) if child.is_a?(Parser::AST::Node)
          end
        end

        def analyze_send(node, result)
          _receiver, method_name = *node
          method_sym = method_name.is_a?(Symbol) ? method_name : nil
          return unless method_sym

          if MUTATING_METHODS.include?(method_sym)
            result[:has_side_effects] = true
          end
        end
      end
    end
  end
end
