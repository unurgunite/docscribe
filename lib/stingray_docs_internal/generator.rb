# frozen_string_literal: true

module StingrayDocsInternal # :nodoc:
  module Generator # :nodoc:
    class << self
      # Generate documentation block(s) for all classes/modules in code.
      # Returns a single String containing class/module stubs with method doc blocks.
      def generate_documentation(code)
        YARD::Registry.clear
        YARD.parse_string(code)

        YARD::Registry.all(:class, :module).map do |ns|
          class_name = ns.name
          pub = public_methods(ns, class_name).compact
          priv = private_methods(ns, class_name).compact
          prot = protected_methods(ns, class_name).compact
          priv_block = priv.empty? ? nil : "# private\n#{priv.join("\n\n").rstrip}"
          prot_block = prot.empty? ? nil : "# protected\n#{prot.join("\n\n").rstrip}"
          docstring(ns.type, class_name, pub.join("\n\n"), priv_block, prot_block)
        end.join("\n")
      end

      private

      def public_methods(ns, class_name)
        ns.meths(inherited: false).map do |m|
          next unless m.visibility == :public

          docs_for_method(class_name, m)
        end
      end

      def private_methods(ns, class_name)
        ns.meths(inherited: false).map do |m|
          next unless m.visibility == :private

          docs_for_method(class_name, m, private: true)
        end
      end

      def protected_methods(ns, class_name)
        ns.meths(inherited: false).map do |m|
          next unless m.visibility == :protected

          docs_for_method(class_name, m)
        end
      end

      def docs_for_method(class_name, method_obj, private: false)
        attrs = method_attributes(method_obj)

        # Respect existing user tags: skip generating ours if present
        params_block = user_has_params?(method_obj) ? nil : attrs[:params_block]
        return_block = user_has_return?(method_obj) ? nil : "# @return [#{attrs[:return_type]}]\n"

        tags = [params_block, return_block].compact.join

        <<~DOC.split("\n").map { |n| "  #{n}" }.join("\n")
          # +#{class_name}#{attrs[:method_symbol]}#{attrs[:method_name]}+    -> #{attrs[:return_type]}
          #
          # Method documentation.
          #
          #{tags}#{attrs[:source]}
        DOC
      end

      # Add these helpers under `private` in the same class/module
      def user_has_params?(method_obj)
        !method_obj.tags(:param).empty? || !method_obj.tags(:option).empty?
      end

      def user_has_return?(method_obj)
        !method_obj.tags(:return).empty?
      end

      def method_attributes(method_obj)
        {
          method_name: method_obj.name,
          method_symbol: (method_obj.scope == :instance ? '#' : '.'),
          return_type: infer_return(method_obj),
          source: (method_obj.source || '').lines.join,
          params_block: build_params_block(method_obj)
        }
      end

      def build_params_block(method_obj)
        lines = method_obj.parameters.map do |raw_name, default|
          name_str = raw_name.to_s
          next nil if name_str == '...'

          ty = Infer.infer_param_type(name_str, default)
          # strip &, *, ** and trailing :
          pname = name_str.sub(/\A[*&]{1,2}/, '').sub(/:$/, '')
          "# @param [#{ty}] #{pname} Param documentation."
        end
        lines.compact!
        return nil if lines.empty?

        "#{lines.join("\n")}\n"
      end

      def infer_return(method_obj)
        # Try to infer from method body first, else default to Object
        Infer.infer_return_type(method_obj.source || '')
      end

      def docstring(struct_type, class_name, methods, private_methods_block, protected_methods_block)
        content = [
          "#{struct_type} #{class_name}",
          methods,
          private_methods_block,
          protected_methods_block
        ].compact.join("\n")

        <<~DOC.rstrip
          #{content}
          end
        DOC
      end
    end
  end
end
