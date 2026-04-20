# frozen_string_literal: true

module Docscribe
  module Plugin
    module Base
      # Base class for collector plugins.
      #
      # CollectorPlugins receive the raw AST and source buffer directly.
      # They walk the tree themselves and return insertion targets that
      # Docscribe will document according to the selected strategy.
      #
      # Idempotency is handled by Docscribe:
      # - :safe       => skip if a doc-like block already exists above anchor_node
      # - :aggressive => replace existing doc block above anchor_node
      #
      # @example Minimal plugin
      #   class MyPlugin < Docscribe::Plugin::Base::CollectorPlugin
      #     def collect(ast, buffer)
      #       results = []
      #
      #       ASTWalk.walk(ast) do |node|
      #         next unless node.type == :send
      #         recv, meth, *args = *node
      #         next unless recv.nil? && meth == :my_dsl_method
      #
      #         results << {
      #           anchor_node: node,
      #           doc: "# My generated doc\n# @return [void]\n"
      #         }
      #       end
      #
      #       results
      #     end
      #   end
      #
      #   Docscribe::Plugin::Registry.register(MyPlugin.new)
      class CollectorPlugin
        # Walk the AST and return documentation insertion targets.
        #
        # Each result is a Hash with:
        # - :anchor_node => Parser::AST::Node — node above which to insert doc
        # - :doc         => String — complete doc block including newlines
        #
        # @param [Parser::AST::Node] ast root AST node of the file
        # @param [Parser::Source::Buffer] buffer source buffer
        # @param [Object] _ast Param documentation.
        # @param [Object] _buffer Param documentation.
        # @return [Array<Hash>]
        def collect(_ast, _buffer)
          []
        end
      end
    end
  end
end
