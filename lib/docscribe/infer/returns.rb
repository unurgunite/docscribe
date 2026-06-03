# frozen_string_literal: true

module Docscribe
  module Infer
    # Return type inference and rescue-conditional return extraction.
    module Returns
      module_function

      # Infer a return type from a full method definition source string.
      #
      # The source must parse to a `:def` or `:defs` node. If parsing fails or inference
      # is uncertain, the fallback type is returned.
      #
      # @note module_function: when included, also defines #infer_return_type (instance visibility: private)
      # @param [String, nil] method_source full method definition source
      # @raise [Parser::SyntaxError]
      # @return [String]
      def infer_return_type(method_source)
        return FALLBACK_TYPE if method_source.nil? || method_source.strip.empty?

        buffer = Parser::Source::Buffer.new('(method)')
        buffer.source = method_source
        root = Docscribe::Parsing.parse_buffer(buffer)
        return FALLBACK_TYPE unless root && %i[def defs].include?(root.type)

        body = root.children.last
        local_var_types = build_local_variable_types(body)
        run_last_expr_type(body, fallback_type: FALLBACK_TYPE, nil_as_optional: true,
                                 local_var_types: local_var_types) || FALLBACK_TYPE
      rescue Parser::SyntaxError
        FALLBACK_TYPE
      end

      # Infer a method's normal return type from an already parsed def/defs node.
      #
      # @note module_function: when included, also defines #infer_return_type_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @return [String]
      def infer_return_type_from_node(node)
        body =
          case node.type
          when :def then node.children[2]
          when :defs then node.children[3]
          end

        return FALLBACK_TYPE unless body

        local_var_types = build_local_variable_types(body)
        run_last_expr_type(body, fallback_type: FALLBACK_TYPE, nil_as_optional: true,
                                 local_var_types: local_var_types) || FALLBACK_TYPE
      end

      # Return a structured return-type spec for a method node.
      #
      # The result includes:
      # - `:normal`  => normal/happy-path return type
      # - `:rescues` => array of `[exception_names, return_type]` pairs for rescue branches
      #
      # @note module_function: when included, also defines #returns_spec_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @param [String] fallback_type type used when inference is uncertain
      # @param [Boolean] nil_as_optional whether `nil` unions should be rendered as optional types
      # @param [nil] core_rbs_provider core RBS type lookup provider
      # @param [nil] param_types parameter name -> type map
      # @return [Hash]
      def returns_spec_from_node(node, fallback_type: FALLBACK_TYPE, nil_as_optional: true, core_rbs_provider: nil,
                                 param_types: nil)
        body =
          case node.type
          when :def then node.children[2]
          when :defs then node.children[3]
          end

        spec = { normal: FALLBACK_TYPE, rescues: [] }
        return spec unless body

        local_var_types = build_local_variable_types(body)

        if body.type == :rescue
          process_rescue_body(spec, body, fallback_type: fallback_type,
                                          nil_as_optional: nil_as_optional, core_rbs_provider: core_rbs_provider,
                                          param_types: param_types)
        else
          spec[:normal] =
            run_last_expr_type(body, fallback_type: fallback_type, nil_as_optional: nil_as_optional,
                                     core_rbs_provider: core_rbs_provider, param_types: param_types,
                                     local_var_types: local_var_types) || FALLBACK_TYPE
        end

        spec
      end

      # Process a rescue body node and populate spec with normal + rescue return types.
      # Method documentation.
      #
      # @note module_function: when included, also defines #process_rescue_body (instance visibility: private)
      # @param [Object] spec Param documentation.
      # @param [Object] body Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] nil_as_optional Param documentation.
      # @param [Object] core_rbs_provider Param documentation.
      # @param [Object] param_types Param documentation.
      # @return [Object]
      def process_rescue_body(spec, body, fallback_type:, nil_as_optional:,
                              core_rbs_provider:, param_types:)
        main_body = body.children[0]
        all_local_var_types = build_local_variable_types(body)
        spec[:normal] =
          run_last_expr_type(main_body, fallback_type: fallback_type, nil_as_optional: nil_as_optional,
                                        core_rbs_provider: core_rbs_provider, param_types: param_types,
                                        local_var_types: all_local_var_types) || FALLBACK_TYPE

        body.children.each do |ch|
          next unless ch.is_a?(Parser::AST::Node) && ch.type == :resbody

          exc_list, _asgn, rescue_body = *ch
          exc_names = Raises.exception_names_from_rescue_list(exc_list)
          rtype =
            run_last_expr_type(rescue_body, fallback_type: fallback_type, nil_as_optional: nil_as_optional,
                                            core_rbs_provider: core_rbs_provider, param_types: param_types,
                                            local_var_types: all_local_var_types) ||
            fallback_type
          spec[:rescues] << [exc_names, rtype]
        end
      end

      # Build a map of local/global/ivar/constant assignments to inferred types.
      #
      # @note module_function: when included, also defines #build_local_variable_types (instance visibility: private)
      # @param [Parser::AST::Node] node AST node to walk
      # @return [Hash, nil]
      def build_local_variable_types(node)
        types = {}
        ASTWalk.walk(node) do |n|
          collect_assignment_type(n, types)
        end
        types.empty? ? nil : types
      end

      # Collect a single assignment node's type into the types hash.
      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_assignment_type (instance visibility: private)
      # @param [Object] node Param documentation.
      # @param [Object] types Param documentation.
      # @return [Object]
      def collect_assignment_type(node, types)
        case node.type
        when :lvasgn, :gvasgn, :ivasgn
          name = node.children[0].to_s
          value = node.children[1]
        when :casgn
          name = node.children[0].to_s
          value = node.children[2]
        else
          return
        end

        return unless value

        inferred = Literals.type_from_literal(value, fallback_type: FALLBACK_TYPE)
        types[name] = inferred if inferred && inferred != FALLBACK_TYPE
      end

      # Handle `:begin` node for last_expr_type.
      #
      # @note module_function: when included, also defines #handle_begin_node (instance visibility: private)
      # @param [Object] node
      # @param [Hash] opts
      # @return [Object]
      def handle_begin_node(node, **opts)
        run_last_expr_type(node.children.last, **opts)
      end

      # Handle `:if` node for last_expr_type.
      #
      # @note module_function: when included, also defines #handle_if_node (instance visibility: private)
      # @param [Object] node
      # @param [Hash] opts
      # @return [Object]
      def handle_if_node(node, **opts)
        t = run_last_expr_type(node.children[1], **opts)
        e = run_last_expr_type(node.children[2], **opts)
        unify_types(t, e, fallback_type: opts[:fallback_type], nil_as_optional: opts[:nil_as_optional])
      end

      # Handle `:case` node for last_expr_type.
      #
      # @note module_function: when included, also defines #handle_case_node (instance visibility: private)
      # @param [Object] node
      # @param [Hash] opts
      # @return [Object]
      def handle_case_node(node, **opts)
        branches = node.children[1..].compact.flat_map do |child|
          if child.type == :when
            run_last_expr_type(child.children.last, **opts)
          else
            run_last_expr_type(child, **opts)
          end
        end.compact

        if branches.empty?
          opts[:fallback_type]
        else
          branches.reduce do |a, b|
            unify_types(a, b, fallback_type: opts[:fallback_type], nil_as_optional: opts[:nil_as_optional])
          end
        end
      end

      # Handle `:block` node for last_expr_type.
      #
      # @note module_function: when included, also defines #handle_block_node (instance visibility: private)
      # @param [Object] node
      # @param [Hash] opts
      # @return [Object]
      def handle_block_node(node, **opts)
        send_node = node.children[0]
        if send_node&.type == :send
          recv = send_node.children[0]
          meth = send_node.children[1]
          rbs_type = resolve_rbs_for_send(recv, meth, opts[:core_rbs_provider], opts[:local_var_types], opts[:param_types])
          return rbs_type if rbs_type
        end

        run_last_expr_type(node.children[2], **opts)
      end

      # Handle `:send` node for last_expr_type.
      #
      # @note module_function: when included, also defines #handle_send_node (instance visibility: private)
      # @param [Object] node
      # @param [Hash] opts
      # @return [Object]
      def handle_send_node(node, **opts)
        recv = node.children[0]
        meth = node.children[1]

        if opts[:core_rbs_provider]
          rbs_type = resolve_rbs_for_send(recv, meth, opts[:core_rbs_provider], opts[:local_var_types], opts[:param_types])
          return rbs_type if rbs_type
        end

        Literals.type_from_literal(node, fallback_type: opts[:fallback_type])
      end

      # Resolve RBS return type for a send node's receiver, if possible.
      #
      # Handles `:lvar` and chained `:send` receivers.
      #
      # @note module_function: when included, also defines #resolve_rbs_for_send (instance visibility: private)
      # @param [Object] recv Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] core_rbs_provider Param documentation.
      # @param [Object] local_var_types Param documentation.
      # @param [Object] param_types Param documentation.
      # @return [String, nil] resolved type or nil if unresolvable
      def resolve_rbs_for_send(recv, meth, core_rbs_provider, local_var_types, param_types)
        return nil unless core_rbs_provider

        if recv&.type == :lvar
          resolve_lvar_rbs(recv, meth, core_rbs_provider, local_var_types, param_types)
        elsif recv&.type == :send
          resolve_chained_send_rbs(recv, meth, core_rbs_provider, local_var_types, param_types)
        end
      end

      # Resolve RBS return type for an `:lvar` receiver.
      #
      # @private
      # @param [Object] recv
      # @param [Object] meth
      # @param [Object] core_rbs_provider
      # @param [Object] local_var_types
      # @param [Object] param_types
      # @return [String, nil]
      def resolve_lvar_rbs(recv, meth, core_rbs_provider, local_var_types, param_types)
        lvar_name = recv.children.first
        recv_type = nil
        recv_type = local_var_types[lvar_name.to_s] if local_var_types && lvar_name
        recv_type = param_types[lvar_name.to_s] if !recv_type && param_types && lvar_name
        return nil unless recv_type

        rbs_type = resolve_rbs_return_type(recv_type, meth, core_rbs_provider)
        rbs_type unless rbs_type == FALLBACK_TYPE
      end

      # Resolve RBS return type for a chained `:send` receiver.
      #
      # @private
      # @param [Object] recv
      # @param [Object] meth
      # @param [Object] core_rbs_provider
      # @param [Object] local_var_types
      # @param [Object] param_types
      # @return [String, nil]
      def resolve_chained_send_rbs(recv, meth, core_rbs_provider, local_var_types, param_types)
        inner_type = run_last_expr_type(recv, fallback_type: nil, nil_as_optional: false,
                                              core_rbs_provider: core_rbs_provider, param_types: param_types,
                                              local_var_types: local_var_types)
        return nil unless inner_type

        rbs_type = resolve_rbs_return_type(inner_type, meth, core_rbs_provider)
        rbs_type unless rbs_type == FALLBACK_TYPE
      end

      # Infer the type of the last expression in a node.
      #
      # Supports:
      # - `begin` groups
      # - `if` branches
      # - `case` expressions
      # - explicit `return`
      # - literal-like expressions via {Literals.type_from_literal}
      # - method calls with RBS core type lookup
      #
      # @note module_function: when included, also defines #last_expr_type (instance visibility: private)
      # @param [Parser::AST::Node, nil] node expression node
      # @param [String] fallback_type type used when inference is uncertain
      # @param [Boolean] nil_as_optional whether `nil` unions should be rendered as optional types
      # @param [Object, nil] core_rbs_provider optional RBS provider for core type lookup
      # @param [Hash, nil] param_types parameter name -> type map for lvar resolution
      # @param [nil] local_var_types pre-built local variable types map
      # @return [String, nil]
      def last_expr_type(node, fallback_type:, nil_as_optional:, core_rbs_provider: nil, param_types: nil,
                         local_var_types: nil)
        run_last_expr_type(node, fallback_type: fallback_type, nil_as_optional: nil_as_optional,
                                 core_rbs_provider: core_rbs_provider, param_types: param_types,
                                 local_var_types: local_var_types)
      end

      # Dispatch `last_expr_type` based on node type.
      #
      # @note module_function: when included, also defines #run_last_expr_type (instance visibility: private)
      # @param [Parser::AST::Node, nil] node
      # @param [Hash] opts options passed through as keyword args
      # @return [String, nil]
      def run_last_expr_type(node, **opts)
        return nil unless node

        case node.type
        when :begin then handle_begin_node(node, **opts)
        when :if then handle_if_node(node, **opts)
        when :case then handle_case_node(node, **opts)
        when :return then Literals.type_from_literal(node.children.first, fallback_type: opts[:fallback_type])
        when :block then handle_block_node(node, **opts)
        when :send then handle_send_node(node, **opts)
        else Literals.type_from_literal(node, fallback_type: opts[:fallback_type])
        end
      end

      # Resolve an RBS return type for a method call.
      #
      # @note module_function: when included, also defines #resolve_rbs_return_type (instance visibility: private)
      # @param [String] container_type class or module name
      # @param [String] method_name method name
      # @param [Object] core_rbs_provider core RBS type lookup provider
      # @return [String] inferred return type
      def resolve_rbs_return_type(container_type, method_name, core_rbs_provider)
        return FALLBACK_TYPE unless core_rbs_provider

        sig = core_rbs_provider.signature_for(
          container: container_type,
          scope: :instance,
          name: method_name
        )

        sig&.return_type || FALLBACK_TYPE
      end

      # Unify two inferred types into a single type string.
      #
      # Rules:
      # - identical types remain unchanged
      # - `nil` unions may become optional types if enabled
      # - otherwise falls back conservatively to `fallback_type`
      #
      # @note module_function: when included, also defines #unify_types (instance visibility: private)
      # @param [String, nil] a
      # @param [String, nil] b
      # @param [String] fallback_type
      # @param [Boolean] nil_as_optional
      # @return [String, nil]
      def unify_types(a, b, fallback_type:, nil_as_optional:)
        a ||= fallback_type
        b ||= fallback_type
        return a if a == b

        if a == 'nil' || b == 'nil'
          non_nil = (a == 'nil' ? b : a)
          return nil_as_optional ? "#{non_nil}?" : "#{non_nil}, nil"
        end

        fallback_type
      end
    end
  end
end
