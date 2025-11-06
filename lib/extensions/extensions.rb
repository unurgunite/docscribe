# frozen_string_literal: true

require 'yard'
require 'parser/current'

# Ensure original classes are loaded before reopening
begin
  require 'yard/handlers/base'
  require 'yard/handlers/ruby/visibility_handler'
rescue LoadError
  # Older versions may not expose these directly; the patch still likely works if require 'yard' loaded them.
end

# @see https://github.com/lsegal/yard/issues/1496
module YARD
  module Handlers
    class Base
      def register_visibility(object, visibility = self.visibility)
        return unless object.respond_to?(:visibility=)
        return if object.is_a?(YARD::CodeObjects::NamespaceObject)

        if object.is_a?(YARD::CodeObjects::MethodObject)
          origin = (globals.respond_to?(:visibility_origin) ? globals.visibility_origin : nil)
          if origin == :keyword
            object.visibility = visibility if object.scope == scope
          else
            object.visibility = visibility
          end
        else
          object.visibility = visibility
        end
      end
    end
  end
end

module YARD
  module Handlers
    module Ruby
      class VisibilityHandler < Base
        process do
          return if (ident = statement.jump(:ident)) == statement

          case statement.type
          when :var_ref, :vcall
            self.visibility = ident.first.to_sym
            globals.visibility_origin = :keyword
          else
            super()
          end
        end
      end
    end
  end
end
