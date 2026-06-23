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
      # @note module_function: defines #infer_return_type (visibility: private)
      # @param [String?] method_source full method definition source
      # @raise [Parser::SyntaxError]
      # @return [String] if Parser::SyntaxError
      # @return [FALLBACK_TYPE] if Parser::SyntaxError
      def infer_return_type(method_source)
        return FALLBACK_TYPE if method_source.nil? || method_source.strip.empty?

        root = parse_method_source(method_source)
        return FALLBACK_TYPE unless root && %i[def defs].include?(root.type)

        body = root.children.last
        local_var_types = build_local_variable_types(body)
        run_last_expr_type(body, fallback_type: FALLBACK_TYPE, nil_as_optional: true,
                                 local_var_types: local_var_types) || FALLBACK_TYPE
      rescue Parser::SyntaxError # steep:ignore
        FALLBACK_TYPE
      end

      # Parse a Ruby source string into an AST using the Parser gem.
      #
      # @note module_function: defines #parse_method_source (visibility: private)
      # @param [String] method_source the method definition source string to parse
      # @return [Parser::AST::Node, nil]
      def parse_method_source(method_source)
        buffer = Parser::Source::Buffer.new('(method)')
        buffer.source = method_source
        Docscribe::Parsing.parse_buffer(buffer)
      end

      # Infer a method's normal return type from an already parsed def/defs node.
      #
      # @note module_function: defines #infer_return_type_from_node (visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @return [String]
      def infer_return_type_from_node(node)
        body = extract_def_body(node)
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
      # @note module_function: defines #returns_spec_from_node (visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @param [String] fallback_type type used when inference is uncertain
      # @param [Boolean] nil_as_optional whether `nil` unions should be rendered as optional types
      # @param [Object?] core_rbs_provider core RBS type lookup provider
      # @param [Hash<String, String>?] param_types parameter name -> type map
      # @param [String?] container
      # @param [nil] signature_provider
      # @return [Object]
      def returns_spec_from_node(node, fallback_type: FALLBACK_TYPE, nil_as_optional: true, core_rbs_provider: nil,  # rubocop:disable Metrics/ParameterLists
                                 param_types: nil, container: nil, signature_provider: nil)
        body = extract_def_body(node)
        spec = { normal: FALLBACK_TYPE, rescues: [] } #: Hash[Symbol, untyped]
        return spec unless body

        types = build_local_variable_types(body, core_rbs_provider: core_rbs_provider, param_types: param_types)
        populate_returns_spec(spec, body, types, fallback_type: fallback_type, nil_as_optional: nil_as_optional,
                                                 core_rbs_provider: core_rbs_provider, param_types: param_types,
                                                 container: container, signature_provider: signature_provider)
        spec
      end

      # Extract the body child node from a `:def` or `:defs` AST node.
      #
      # @note module_function: defines #extract_def_body (visibility: private)
      # @param [Parser::AST::Node] node a `:def` or `:defs` AST node
      # @return [Parser::AST::Node, nil]
      def extract_def_body(node)
        case node.type
        when :def then node.children[2]
        when :defs then node.children[3]
        end
      end

      # Populate the spec hash with normal and/or rescue return types from the body.
      #
      # @note module_function: defines #populate_returns_spec (visibility: private)
      # @param [Object] spec the return spec hash to populate
      # @param [Parser::AST::Node] body the method body AST node
      # @param [Hash<Object, Object>, nil] local_var_types inferred local variable type map
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Object]
      def populate_returns_spec(spec, body, local_var_types, **opts)
        if body.type == :rescue
          process_rescue_body(spec, body, **opts)
        else
          spec[:normal] = infer_normal_return_type(body, **opts, local_var_types: local_var_types)
        end
      end

      # Infer the normal (non-rescue) return type from a method body node.
      #
      # @note module_function: defines #infer_normal_return_type (visibility: private)
      # @param [Parser::AST::Node] body the method body AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String]
      def infer_normal_return_type(body, **opts)
        run_last_expr_type(body, **opts) || FALLBACK_TYPE
      end

      # Process a :rescue body node and populate spec with normal + rescue return types.
      #
      # @note module_function: defines #process_rescue_body (visibility: private)
      # @param [Object] spec the return spec hash to populate
      # @param [Parser::AST::Node] body the :rescue AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Object]
      def process_rescue_body(spec, body, **opts)
        main_body = body.children[0]
        local_var_types = build_local_variable_types(body,
                                                     core_rbs_provider: opts[:core_rbs_provider],
                                                     param_types: opts[:param_types])
        rescue_opts = opts.merge(local_var_types: local_var_types)
        spec[:normal] = run_last_expr_type(main_body, **rescue_opts) || FALLBACK_TYPE
        process_rescue_branches(spec, body, **rescue_opts)
      end

      # Extract return types from each :resbody child and append to spec[:rescues].
      #
      # @note module_function: defines #process_rescue_branches (visibility: private)
      # @param [Object] spec the return spec hash to populate
      # @param [Parser::AST::Node] body the :rescue AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Array<Object>] the list of rescue type entries
      def process_rescue_branches(spec, body, **opts)
        body.children.each do |ch|
          next unless ch.is_a?(Parser::AST::Node) && ch.type == :resbody

          exc_list, _asgn, rescue_body = *ch
          exc_names = Raises.exception_names_from_rescue_list(exc_list)
          rtype = run_last_expr_type(rescue_body, **opts) || opts[:fallback_type]
          spec[:rescues] << [exc_names, rtype]
        end
      end

      # Build a map of local/global/ivar/constant assignments to inferred types.
      #
      # @note module_function: defines #build_local_variable_types (visibility: private)
      # @param [Parser::AST::Node] node AST node to walk
      # @param [Object] opts additional keyword options forwarded to inference
      # @return [Hash<String, String>, nil]
      def build_local_variable_types(node, **opts)
        types = {} #: Hash[String, String]
        ASTWalk.walk(node) do |n|
          collect_assignment_type(n, types, **opts)
        end
        types.empty? ? nil : types
      end

      # Infer the type of a single assignment node and store it in the types hash.
      #
      # Uses `run_last_expr_type` when `core_rbs_provider` is available to
      # resolve send expressions (e.g., `x = 123 + 1` -> `Integer`).
      # Falls back to `Literals.type_from_literal` for plain literals.
      #
      # @note module_function: defines #collect_assignment_type (visibility: private)
      # @param [Parser::AST::Node] node an assignment AST node
      # @param [Hash<String, String>] types the accumulated local variable type map
      # @param [Object] opts additional keyword options forwarded to inference
      # @return [void]
      def collect_assignment_type(node, types, **opts)
        name, value = assignment_name_and_value(node)
        return unless name && value

        inferred = if opts[:core_rbs_provider]
                     run_last_expr_type(value, **opts, fallback_type: FALLBACK_TYPE,
                                                       nil_as_optional: false, local_var_types: types)
                   else
                     Literals.type_from_literal(value, fallback_type: FALLBACK_TYPE)
                   end
        types[name] = inferred if inferred && inferred != FALLBACK_TYPE
      end

      # Extract the variable name and value expression from an assignment node.
      #
      # @note module_function: defines #assignment_name_and_value (visibility: private)
      # @param [Parser::AST::Node] node an assignment AST node (:lvasgn, :gvasgn, :ivasgn, :casgn, :op_asgn)
      # @return [(String, nil, Parser::AST::Node, nil)]
      def assignment_name_and_value(node)
        case node.type
        when :lvasgn, :gvasgn, :ivasgn, :cvasgn
          [node.children[0].to_s, node.children[1]]
        when :casgn
          constant_name_and_value(node)
        when :op_asgn
          compound_name_and_value(node)
        else
          [nil, nil]
        end
      end

      # Extract the name and value from a `:casgn` (constant assignment) node.
      #
      # @note module_function: defines #constant_name_and_value (visibility: private)
      # @param [Parser::AST::Node] node the `:casgn` AST node
      # @return [(String, nil, Parser::AST::Node, nil)]
      def constant_name_and_value(node)
        [node.children[0].to_s, node.children[2]]
      end

      # Extract the name and value from an `:op_asgn` (compound assignment) node.
      #
      # @note module_function: defines #compound_name_and_value (visibility: private)
      # @param [Parser::AST::Node] node the `:op_asgn` AST node
      # @return [(String, nil, Parser::AST::Node, nil)]
      def compound_name_and_value(node)
        [node.children[0].children.first.to_s, node.children[2]]
      end

      # Handle `:lvar` node for last_expr_type — look up the variable in local_var_types.
      #
      # @note module_function: defines #handle_lvar_node (visibility: private)
      # @param [Parser::AST::Node] node the `:lvar` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_lvar_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) || opts[:fallback_type]
      end

      # Handle `:ivar` node for last_expr_type — look up instance variable in local_var_types.
      #
      # @note module_function: defines #handle_ivar_node (visibility: private)
      # @param [Parser::AST::Node] node the `:ivar` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_ivar_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) || opts[:fallback_type]
      end

      # Handle `:gvar` node for last_expr_type — look up global variable in local_var_types.
      #
      # @note module_function: defines #handle_gvar_node (visibility: private)
      # @param [Parser::AST::Node] node the `:gvar` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_gvar_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) || opts[:fallback_type]
      end

      # Handle `:cvar` node for last_expr_type — look up class variable in local_var_types.
      #
      # @note module_function: defines #handle_cvar_node (visibility: private)
      # @param [Parser::AST::Node] node the `:cvar` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_cvar_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) || opts[:fallback_type]
      end

      # Handle `:lvasgn` node for last_expr_type — look up local var assignment in local_var_types.
      #
      # @note module_function: defines #handle_lvasgn_node (visibility: private)
      # @param [Parser::AST::Node] node the `:lvasgn` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_lvasgn_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) ||
          run_last_expr_type(node.children[1], **opts) ||
          opts[:fallback_type]
      end

      # Handle `:ivasgn` node for last_expr_type — look up ivar assignment in local_var_types.
      #
      # @note module_function: defines #handle_ivasgn_node (visibility: private)
      # @param [Parser::AST::Node] node the `:ivasgn` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_ivasgn_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) ||
          run_last_expr_type(node.children[1], **opts) ||
          opts[:fallback_type]
      end

      # Handle `:gvasgn` node for last_expr_type — look up global var assignment in local_var_types.
      #
      # @note module_function: defines #handle_gvasgn_node (visibility: private)
      # @param [Parser::AST::Node] node the `:gvasgn` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_gvasgn_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) ||
          run_last_expr_type(node.children[1], **opts) ||
          opts[:fallback_type]
      end

      # Handle `:cvasgn` node for last_expr_type — look up class var assignment in local_var_types.
      #
      # @note module_function: defines #handle_cvasgn_node (visibility: private)
      # @param [Parser::AST::Node] node the `:cvasgn` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_cvasgn_node(node, **opts)
        name = node.children[0].to_s
        opts[:local_var_types]&.fetch(name, nil) ||
          run_last_expr_type(node.children[1], **opts) ||
          opts[:fallback_type]
      end

      # Handle `:op_asgn` node (compound assignment: `x += 1`, `@var -= 2`, etc.).
      #
      # Infers the result type from the operator and the right operand's type.
      # Uses RBS to resolve when available (e.g., `Integer#+` -> `Integer`).
      #
      # @note module_function: defines #handle_op_asgn_node (visibility: private)
      # @param [Parser::AST::Node] node the `:op_asgn` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_op_asgn_node(node, **opts)
        meth = node.children[1]
        return nil unless %i[+ - * / % ** << | & ^].include?(meth)
        return nil unless opts[:core_rbs_provider]

        arg = node.children[2]
        arg_type = type_from_literal_safe(arg)
        return nil unless arg_type

        rbs = resolve_rbs_return_type(arg_type, meth, opts[:core_rbs_provider])
        rbs unless rbs == FALLBACK_TYPE
      end

      # Handle `:begin` node for last_expr_type.
      #
      # @note module_function: defines #handle_begin_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_begin_node(node, **opts)
        run_last_expr_type(node.children.last, **opts)
      end

      # Handle `:if` node for last_expr_type.
      #
      # @note module_function: defines #handle_if_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_if_node(node, **opts)
        t = run_last_expr_type(node.children[1], **opts)
        e = if node.children[2]
              run_last_expr_type(node.children[2], **opts)
            else
              'nil'
            end
        unify_types(t, e, fallback_type: opts[:fallback_type] || 'untyped',
                          nil_as_optional: opts.fetch(:nil_as_optional, true))
      end

      # Handle `:case` node for last_expr_type.
      #
      # @note module_function: defines #handle_case_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_case_node(node, **opts)
        branches = process_case_branches(node, **opts)
        if branches.empty?
          opts[:fallback_type]
        else
          branches.reduce do |a, b|
            unify_types(a, b, fallback_type: opts[:fallback_type] || 'untyped',
                              nil_as_optional: opts.fetch(:nil_as_optional, true))
          end
        end
      end

      # Handle `:or` node (`a || b`) for last_expr_type.
      #
      # The result type is the union of both sides, since either may be returned
      # depending on the truthiness of the left operand.
      #
      # @note module_function: defines #handle_or_node (visibility: private)
      # @param [Parser::AST::Node] node the `:or` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_or_node(node, **opts)
        t = run_last_expr_type(node.children[0], **opts)
        e = run_last_expr_type(node.children[1], **opts)
        unify_types(t, e, fallback_type: opts[:fallback_type] || 'untyped',
                          nil_as_optional: opts.fetch(:nil_as_optional, true))
      end

      # Handle `:and` node (`a && b`) for last_expr_type.
      #
      # The result type is the union of both sides, since either may be returned
      # depending on the truthiness of the left operand.
      #
      # @note module_function: defines #handle_and_node (visibility: private)
      # @param [Parser::AST::Node] node the `:and` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_and_node(node, **opts)
        t = run_last_expr_type(node.children[0], **opts)
        e = run_last_expr_type(node.children[1], **opts)
        unify_types(t, e, fallback_type: opts[:fallback_type] || 'untyped',
                          nil_as_optional: opts.fetch(:nil_as_optional, true))
      end

      # Handle `:kwbegin` node (`begin; expr; end`) for last_expr_type.
      #
      # Unwraps the explicit begin node and delegates to the inner expression,
      # which may be a `:rescue` or `:ensure` node.
      #
      # @note module_function: defines #handle_kwbegin_node (visibility: private)
      # @param [Parser::AST::Node] node the `:kwbegin` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_kwbegin_node(node, **opts)
        run_last_expr_type(node.children.first, **opts)
      end

      # Handle `:rescue` node for last_expr_type.
      #
      # Supports both inline rescue (`expr rescue default`) and block rescue
      # (`begin; expr; rescue; e; end`).
      #
      # @note module_function: defines #handle_rescue_node (visibility: private)
      # @param [Parser::AST::Node] node the `:rescue` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_rescue_node(node, **opts)
        branches = collect_rescue_branches(node, **opts)
        branches.reduce do |a, b|
          unify_types(a, b, fallback_type: opts[:fallback_type] || 'untyped',
                            nil_as_optional: opts.fetch(:nil_as_optional, true))
        end
      end

      # Handle `:rescue` node for last_expr_type.
      #
      # Unifies the body type with all rescue handler types and the optional else clause.
      # Collect all rescue branch return types from a `:rescue` AST node.
      #
      # @note module_function: defines #collect_rescue_branches (visibility: private)
      # @param [Parser::AST::Node] node the `:rescue` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Array<String, nil>]
      def collect_rescue_branches(node, **opts)
        branches = [run_last_expr_type(node.children[0], **opts)]
        (node.children[1..] || []).each do |child|
          if child.is_a?(Parser::AST::Node) && child.type == :resbody
            handler = child.children[2]
            branches << run_last_expr_type(handler, **opts) if handler
          else
            branches << run_last_expr_type(child, **opts)
          end
        end
        branches
      end

      # Handle `:ensure` node (`begin; expr; ensure; cleanup; end`) for last_expr_type.
      #
      # The ensure clause's result is discarded by Ruby; only the body type is returned.
      #
      # @note module_function: defines #handle_ensure_node (visibility: private)
      # @param [Parser::AST::Node] node the `:ensure` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_ensure_node(node, **opts)
        run_last_expr_type(node.children[0], **opts)
      end

      # Handle `:defined?` node (`defined?(expr)`) for last_expr_type.
      #
      # Returns `nil` if the expression is not defined, or a String description
      # if it is defined. The union type is `String?`.
      #
      # @note module_function: defines #handle_defined_node (visibility: private)
      # @param [Parser::AST::Node] _node the `:defined?` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_defined_node(_node, **opts)
        nil_as_optional = opts.fetch(:nil_as_optional, true)
        nil_as_optional ? 'String?' : 'String, nil'
      end

      # Handle `:zsuper` node (`super` with no arguments) for last_expr_type.
      #
      # Returns the super method's return type if resolvable via RBS, or the
      # fallback type otherwise.
      #
      # @note module_function: defines #handle_zsuper_node (visibility: private)
      # @param [Parser::AST::Node] _node the `:zsuper` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_zsuper_node(_node, **opts)
        opts[:fallback_type]
      end

      # Handle `:super` node (`super(args)`) for last_expr_type.
      #
      # Returns the super method's return type if resolvable via RBS, or the
      # fallback type otherwise.
      #
      # @note module_function: defines #handle_super_node (visibility: private)
      # @param [Parser::AST::Node] _node the `:super` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_super_node(_node, **opts)
        opts[:fallback_type]
      end

      # Handle `:yield` node (`yield` / `yield(args)`) for last_expr_type.
      #
      # Returns the block's return type if resolvable via RBS (`Proc#call`),
      # or the fallback type otherwise.
      #
      # @note module_function: defines #handle_yield_node (visibility: private)
      # @param [Parser::AST::Node] _node the `:yield` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_yield_node(_node, **opts)
        opts[:fallback_type]
      end

      # Handle `:case_match` node (`case x; in pat; expr; end`) for last_expr_type.
      #
      # Similar to `:case` — unifies all `in_pattern` branch types and the optional else clause.
      #
      # @note module_function: defines #handle_case_match_node (visibility: private)
      # @param [Parser::AST::Node] node the `:case_match` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_case_match_node(node, **opts)
        branches = process_pattern_branches(node, **opts)
        if branches.empty?
          opts[:fallback_type]
        else
          branches.reduce do |a, b|
            unify_types(a, b, fallback_type: opts[:fallback_type] || 'untyped',
                              nil_as_optional: opts.fetch(:nil_as_optional, true))
          end
        end
      end

      # Handle `:in_pattern` node (pattern inside `case...in`) for last_expr_type.
      #
      # Extracts the body expression from the pattern and recurses.
      #
      # @note module_function: defines #handle_in_pattern_node (visibility: private)
      # @param [Parser::AST::Node] node the `:in_pattern` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_in_pattern_node(node, **opts)
        run_last_expr_type(node.children[2], **opts)
      end

      # Extract inferred return types from all in_pattern branches of a :case_match expression.
      #
      # @note module_function: defines #process_pattern_branches (visibility: private)
      # @param [Parser::AST::Node] node the :case_match AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Array<String>] list of inferred types from each branch
      def process_pattern_branches(node, **opts)
        (node.children[1..] || []).compact.filter_map do |child|
          run_last_expr_type(child, **opts) if child.is_a?(Parser::AST::Node)
        end
      end

      # Extract inferred return types from all branches of a :case expression.
      #
      # @note module_function: defines #process_case_branches (visibility: private)
      # @param [Parser::AST::Node] node the :case AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [Array<String>] list of inferred types from each branch
      def process_case_branches(node, **opts)
        (node.children[1..] || []).compact.flat_map do |child|
          if child.type == :when
            run_last_expr_type(child.children.last, **opts)
          else
            run_last_expr_type(child, **opts)
          end
        end.compact
      end

      # Handle `:block` node for last_expr_type.
      #
      # @note module_function: defines #handle_block_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil] rubocop:disable Metrics/AbcSize
      def handle_block_node(node, **opts)
        send_node = node.children[0]
        if send_node&.type == :send
          recv = send_node.children[0]
          meth = send_node.children[1]
          rbs_type = resolve_rbs_for_send(recv, meth, opts[:core_rbs_provider], opts[:local_var_types],
                                          opts[:param_types])
          rbs_type ||= container_rbs_return_type(meth, **opts) if recv.nil?
          return rbs_type if rbs_type
        end

        run_last_expr_type(node.children[2], **opts)
      end
      # rubocop:enable Metrics/AbcSize

      # Handle `:send` node for last_expr_type.
      #
      # @note module_function: defines #handle_send_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil] rubocop:disable Metrics/MethodLength
      def handle_send_node(node, **opts)
        recv = node.children[0]
        meth = node.children[1]

        if opts[:core_rbs_provider]
          rbs_type = resolve_rbs_for_send(recv, meth, opts[:core_rbs_provider], opts[:local_var_types],
                                          opts[:param_types])
          rbs_type ||= container_rbs_return_type(meth, **opts) if recv.nil?
          return rbs_type if rbs_type
        end

        compound_type = infer_from_compound_assign(node, **opts)
        return compound_type if compound_type

        Literals.type_from_literal(node, fallback_type: opts[:fallback_type])
      end
      # rubocop:enable Metrics/MethodLength

      # Resolve RBS return type for a send node's receiver, if possible.
      #
      # Handles `:lvar`, chained `:send`, literal (`:int`, `:str`, etc.),
      # and variable (`:ivar`, `:gvar`, `:cvar`) receivers.
      #
      # @note module_function: defines #resolve_rbs_for_send (visibility: private)
      # @param [Parser::AST::Node, nil] recv the receiver node of the send
      # @param [Symbol] meth the method name being called
      # @param [Object, nil] core_rbs_provider optional RBS provider for core type lookup
      # @param [Hash<Object, Object>, nil] local_var_types inferred local variable type map
      # @param [Hash<String, String>, nil] param_types parameter name to type map
      # @return [String, nil] resolved type or nil if unresolvable
      def resolve_rbs_for_send(recv, meth, core_rbs_provider, local_var_types, param_types)
        return nil unless core_rbs_provider

        recv_type = receiver_rbs_type_name(recv, core_rbs_provider, local_var_types, param_types)
        return nil unless recv_type

        rbs = resolve_rbs_return_type(recv_type, meth, core_rbs_provider)
        rbs unless rbs == FALLBACK_TYPE
      end

      # Resolve return type from the current method's container via RBS.
      #
      # Handles implicit self calls (recv is nil) by looking up the method
      # on the container class.
      #
      # @note module_function: defines #container_rbs_return_type (visibility: private)
      # @param [Symbol] meth the method name being called
      # @param [Object] opts additional keyword options (must include :container and :core_rbs_provider)
      # @return [String, nil] resolved type or nil if unresolvable
      def container_rbs_return_type(meth, **opts)
        return unless opts[:container]

        if opts[:core_rbs_provider]
          rbs = resolve_rbs_return_type(opts[:container], meth, opts[:core_rbs_provider])
          return rbs unless rbs == FALLBACK_TYPE
        end

        if opts[:signature_provider]
          sig = opts[:signature_provider].signature_for(container: opts[:container], scope: :instance, name: meth)
          return sig.return_type if sig
        end

        nil
      end

      # Map a receiver AST node to its RBS type name string.
      #
      # Supports local variables, method calls, literals, and instance/global/class variables.
      #
      # @note module_function: when included, also defines #receiver_rbs_type_name (instance visibility: private)
      # @param [Parser::AST::Node, nil] recv the receiver node
      # @param [Object, nil] core_rbs_provider core RBS provider
      # @param [Hash<Object, Object>, nil] local_var_types inferred local variable types
      # @param [Hash<String, String>, nil] param_types parameter name to type map
      # @return [String, nil]
      LITERAL_RBS_TYPES = {
        int: 'Integer', str: 'String', sym: 'Symbol', true: 'Boolean',
        false: 'Boolean', float: 'Float', array: 'Array', hash: 'Hash',
        nil: 'NilClass'
      }.freeze

      # Map receiver AST node to RBS type name.
      #
      # @note module_function: defines #receiver_rbs_type_name (visibility: private)
      # @param [Parser::AST::Node, nil] recv the receiver AST node
      # @param [Object, nil] core_rbs_provider core RBS type provider
      # @param [Hash<Object, Object>, nil] local_var_types inferred local variable types
      # @param [Hash<String, String>, nil] param_types parameter name-to-type map
      # @return [String, nil]
      def receiver_rbs_type_name(recv, core_rbs_provider, local_var_types, param_types)
        return unless recv
        return LITERAL_RBS_TYPES[recv.type] if LITERAL_RBS_TYPES.key?(recv.type)
        return lookup_lvar_type(recv.children.first, local_var_types, param_types) if %i[lvar ivar gvar
                                                                                         cvar].include?(recv.type)
        return unless recv.type == :send

        run_last_expr_type(recv, fallback_type: FALLBACK_TYPE, nil_as_optional: false,
                                 core_rbs_provider: core_rbs_provider,
                                 param_types: param_types,
                                 local_var_types: local_var_types)
      end

      # Infer return type from a compound-assignment-like `:send` by reading the
      # first literal argument's type — only fires when `core_rbs_provider` is
      # present and the argument's RBS return type can be resolved.
      #
      # Enables `@var += 123` -> `Integer` (via `Integer#+`) and similar patterns.
      #
      # @note module_function: defines #infer_from_compound_assign (visibility: private)
      # @param [Parser::AST::Node] node the `:send` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def infer_from_compound_assign(node, **opts)
        return nil unless opts[:core_rbs_provider]

        meth = node.children[1]
        return nil unless %i[+ - * / % ** << | & ^].include?(meth)

        first_arg = node.children[2]
        return nil unless first_arg

        arg_type = type_from_literal_safe(first_arg)
        return nil unless arg_type

        rbs = resolve_rbs_return_type(arg_type, meth, opts[:core_rbs_provider])
        rbs unless rbs == FALLBACK_TYPE
      end

      # Safely get a type string from a literal node, returning nil if the node
      # is not a literal or yields no type.
      #
      # @note module_function: defines #type_from_literal_safe (visibility: private)
      # @param [Parser::AST::Node, nil] node literal AST node
      # @return [String, nil]
      def type_from_literal_safe(node)
        return nil unless node

        t = Literals.type_from_literal(node, fallback_type: FALLBACK_TYPE)
        t unless t == FALLBACK_TYPE
      end

      # Resolve RBS return type for an `:lvar` receiver.
      #
      # @note module_function: defines #resolve_lvar_rbs (visibility: private)
      # @param [Parser::AST::Node?] recv the receiver node of the send
      # @param [Symbol] meth the method name being called
      # @param [Object, nil] core_rbs_provider core RBS type lookup provider
      # @param [Hash<Object, Object>, nil] local_var_types pre-built local variable types map
      # @param [Hash<String, String>, nil] param_types parameter name -> type map for lvar resolution
      # @return [String, nil]
      def resolve_lvar_rbs(recv, meth, core_rbs_provider, local_var_types, param_types)
        lvar_name = recv&.children&.first
        recv_type = lookup_lvar_type(lvar_name, local_var_types, param_types)
        return nil unless recv_type

        rbs_type = resolve_rbs_return_type(recv_type, meth, core_rbs_provider)
        rbs_type unless rbs_type == FALLBACK_TYPE
      end

      # Look up a local variable's inferred type from local or parameter type maps.
      #
      # @note module_function: defines #lookup_lvar_type (visibility: private)
      # @param [Object] lvar_name the local variable name
      # @param [Hash<Object, Object>, nil] local_var_types inferred local variable type map
      # @param [Hash<String, String>, nil] param_types parameter name to type map
      # @return [String, nil]
      def lookup_lvar_type(lvar_name, local_var_types, param_types)
        return local_var_types[lvar_name.to_s] if local_var_types&.key?(lvar_name.to_s)
        return param_types[lvar_name.to_s] if param_types&.key?(lvar_name.to_s)

        nil
      end

      # Resolve RBS return type for a chained `:send` receiver.
      #
      # @note module_function: defines #resolve_chained_send_rbs (visibility: private)
      # @param [Parser::AST::Node?] recv the receiver node of the send
      # @param [Symbol] meth the method name being called
      # @param [Object, nil] core_rbs_provider core RBS type lookup provider
      # @param [Hash<Object, Object>, nil] local_var_types pre-built local variable types map
      # @param [Hash<String, String>, nil] param_types parameter name -> type map for lvar resolution
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
      # @note module_function: defines #last_expr_type (visibility: private)
      # @param [Parser::AST::Node, nil] node expression node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def last_expr_type(node, **opts)
        run_last_expr_type(node, **opts)
      end

      # Dispatch `last_expr_type` based on node type.
      #
      # @note module_function: defines #run_last_expr_type (visibility: private)
      # @param [Parser::AST::Node, nil] node the `:return` AST node
      # @param [Object] opts options passed through as keyword args
      # @return [String, nil]
      def run_last_expr_type(node, **opts)
        return unless node

        type = node.type == :defined? ? :defined : node.type
        method_name = :"handle_#{type}_node"
        if respond_to?(method_name, true)
          send(method_name, node, **opts)
        else
          Literals.type_from_literal(node, fallback_type: opts[:fallback_type])
        end
      end

      # Extract the return type from an explicit `:return` node.
      #
      # @note module_function: defines #handle_return_node (visibility: private)
      # @param [Parser::AST::Node] node the `:return` AST node
      # @param [Object] opts additional keyword options forwarded to type inference
      # @return [String, nil]
      def handle_return_node(node, **opts)
        Literals.type_from_literal(node.children.first, fallback_type: opts[:fallback_type])
      end

      # Resolve an RBS return type for a method call.
      #
      # @note module_function: defines #resolve_rbs_return_type (visibility: private)
      # @param [String] container_type class or module name
      # @param [String, Symbol] method_name method name
      # @param [Object, nil] core_rbs_provider core RBS type lookup provider
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
      # @note module_function: defines #unify_types (visibility: private)
      # @param [String, nil] type_a first type to unify
      # @param [String, nil] type_b second type to unify
      # @param [String] fallback_type type used when neither is nil
      # @param [Boolean] nil_as_optional whether to render nil unions as optional types
      # @return [String]
      def unify_types(type_a, type_b, fallback_type:, nil_as_optional:)
        type_a ||= fallback_type
        type_b ||= fallback_type
        return type_a if type_a == type_b

        unify_nil_types(type_a, type_b, nil_as_optional: nil_as_optional)
      end

      # Unify two types where one may be `nil`, producing optional or union type.
      #
      # @note module_function: defines #unify_nil_types (visibility: private)
      # @param [String] type_a first type string
      # @param [String] type_b second type string
      # @param [Boolean] nil_as_optional whether to render nil unions as optional types
      # @return [String]
      def unify_nil_types(type_a, type_b, nil_as_optional:)
        if type_a == 'nil' || type_b == 'nil'
          non_nil = (type_a == 'nil' ? type_b : type_a)
          return nil_as_optional ? "#{non_nil}?" : "#{non_nil}, nil"
        end

        "#{type_a}, #{type_b}"
      end
    end
  end
end
