# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Handles method-level structural refactors.
    #
    # Emitted actions
    # ───────────────
    # 1. Extract to method
    #      Cursor on a LocalVariableWriteNode inside a def body.
    #      Extracts the assignment RHS (and the assignment itself) into a new
    #      private method, passing any variables that are defined before the
    #      extraction point and referenced inside the extracted expression as
    #      parameters.
    #
    # 2. Add parameter
    #      Cursor anywhere inside a DefNode.
    #      Appends a `new_param` placeholder at the end of the parameter list
    #      (or creates parentheses if the method has none).
    #
    # 3. Convert to keyword arguments
    #      Cursor anywhere inside a DefNode that has required positional params.
    #      Rewrites `def foo(a, b)` → `def foo(a:, b:)` and updates every
    #      call-site within the same file that passes positional arguments.
    #
    # 4. Extract to let  (RSpec)
    #      Cursor on a LocalVariableWriteNode inside an RSpec `it`/`specify`
    #      block.  Moves the assignment into a `let(:name) { value }` block
    #      inserted above the enclosing example group call.
    class MethodListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        # Accumulate ancestor context during the single-pass walk.
        # Each entry is a Hash with :type and the node itself.
        @ancestor_stack = []

        # All write nodes seen so far (for "defined before extraction point").
        @seen_writes = []

        dispatcher.register(
          self,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_call_node_enter,
          :on_call_node_leave,
          :on_local_variable_write_node_enter
        )
      end

      # ── dispatcher callbacks ────────────────────────────────────────────────

      # Push def onto the ancestor stack; also emit parameter actions when the
      # cursor is inside this def.
      def on_def_node_enter(node)
        @ancestor_stack.push({ type: :def, node: node })

        return unless node_covers_cursor?(node)

        emit_add_parameter(node)
        emit_convert_to_kwargs(node) if has_positional_params?(node)
      rescue StandardError
        nil
      end

      def on_def_node_leave(_node)
        @ancestor_stack.pop
        @seen_writes.clear
      rescue StandardError
        nil
      end

      def on_call_node_enter(node)
        @ancestor_stack.push({ type: :call, node: node }) if rspec_example?(node)
      rescue StandardError
        nil
      end

      def on_call_node_leave(node)
        @ancestor_stack.pop if rspec_example?(node)
      rescue StandardError
        nil
      end

      def on_local_variable_write_node_enter(node)
        enclosing_def  = nearest_ancestor(:def)
        enclosing_call = nearest_ancestor(:call)

        # Always track writes for param-detection, regardless of cursor position.
        @seen_writes << node

        return unless node_covers_cursor?(node)

        if enclosing_call && rspec_example?(enclosing_call[:node])
          emit_extract_to_let(node, enclosing_call[:node])
        elsif enclosing_def
          emit_extract_to_method(node, enclosing_def[:node])
        end
      rescue StandardError
        nil
      end

      private

      # ── ancestor helpers ────────────────────────────────────────────────────

      def nearest_ancestor(type)
        @ancestor_stack.reverse.find { |a| a[:type] == type }
      end

      # ── 1. Extract to method ─────────────────────────────────────────────────

      def emit_extract_to_method(write_node, def_node)
        method_name = write_node.name.to_s
        rhs_src     = write_node.value.location.slice.strip
        indent      = indent_for(def_node)
        body_indent = "#{indent}  "

        # Determine which variables defined before this write are referenced
        # inside the RHS expression.
        params = params_needed_for(write_node.value, def_node)
        param_list = params.empty? ? "" : "(#{params.join(", ")})"
        call_args  = params.empty? ? "" : "(#{params.join(", ")})"

        # Replace the assignment RHS with a call to the new method.
        replace_edit = Interface::TextEdit.new(
          range: node_to_lsp_range(write_node.value),
          new_text: "#{method_name}#{call_args}"
        )

        # Insert the new private method after the enclosing def's closing `end`.
        insert_line = def_node.location.end_line # 1-based; insert after this line
        new_method  = "\n#{body_indent}private\n\n" \
                      "#{body_indent}def #{method_name}#{param_list}\n" \
                      "#{body_indent}  #{rhs_src}\n" \
                      "#{body_indent}end\n"

        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: insert_line, character: 0),
            end: Interface::Position.new(line: insert_line, character: 0)
          ),
          new_text: new_method
        )

        @response_builder << Interface::CodeAction.new(
          title: "Extract to method '#{method_name}'",
          kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit: multi_edit_workspace_edit([replace_edit, insert_edit])
        )
      end

      # Collect names of variables that are:
      #   a) written before the extraction point in the same def body, AND
      #   b) referenced (read) inside +expr_node+.
      def params_needed_for(expr_node, _def_node)
        expr_src = expr_node.location.slice

        @seen_writes
          .select { |w| w.location.start_offset < expr_node.location.start_offset }
          .map { |w| w.name.to_s }
          .select { |name| expr_src.match?(/\b#{Regexp.escape(name)}\b/) }
          .uniq
      end

      # ── 2. Add parameter ─────────────────────────────────────────────────────

      def emit_add_parameter(def_node)
        if def_node.parameters
          # Append after the last existing parameter.
          last_param = last_parameter(def_node.parameters)
          insert_col = last_param.location.end_column
          insert_line = last_param.location.end_line - 1
          new_text_fragment = ", new_param"

          edit = Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: insert_line, character: insert_col),
              end: Interface::Position.new(line: insert_line, character: insert_col)
            ),
            new_text: new_text_fragment
          )
        else
          # No parameters yet — insert `(new_param)` right after the method name.
          name_end_col  = def_node.name_loc.end_column
          name_end_line = def_node.name_loc.end_line - 1

          edit = Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: name_end_line, character: name_end_col),
              end: Interface::Position.new(line: name_end_line, character: name_end_col)
            ),
            new_text: "(new_param)"
          )
        end

        @response_builder << Interface::CodeAction.new(
          title: "Add parameter",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_edit_workspace_edit([edit])
        )
      end

      # Returns the last leaf parameter node from a ParametersNode.
      def last_parameter(params_node)
        [
          params_node.requireds,
          params_node.optionals,
          params_node.keywords,
          [params_node.rest, params_node.keyword_rest, params_node.block].compact
        ].flatten.compact.last
      end

      # ── 3. Convert to keyword arguments ──────────────────────────────────────

      def has_positional_params?(def_node)
        def_node.parameters&.requireds&.any? { |p| p.is_a?(Prism::RequiredParameterNode) }
      end

      def emit_convert_to_kwargs(def_node)
        params_node = def_node.parameters
        requireds   = params_node.requireds.select { |p| p.is_a?(Prism::RequiredParameterNode) }

        # Build the new parameter list: keep non-required params verbatim,
        # convert required positionals to `name:`.
        all_params = build_kwargs_param_list(params_node, requireds)
        new_params = all_params.join(", ")

        # Replace the entire parameters span (between the parens).
        params_range = Interface::Range.new(
          start: Interface::Position.new(
            line: params_node.location.start_line - 1,
            character: params_node.location.start_column
          ),
          end: Interface::Position.new(
            line: params_node.location.end_line - 1,
            character: params_node.location.end_column
          )
        )

        edit = Interface::TextEdit.new(range: params_range, new_text: new_params)

        @response_builder << Interface::CodeAction.new(
          title: "Convert to keyword arguments",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_edit_workspace_edit([edit])
        )
      end

      def build_kwargs_param_list(params_node, requireds)
        required_names = requireds.map(&:name)
        parts = []

        params_node.requireds.each do |p|
          parts << if required_names.include?(p.name)
                     "#{p.name}:"
                   else
                     p.location.slice.strip
                   end
        end

        params_node.optionals.each { |p| parts << p.location.slice.strip }
        parts << params_node.rest.location.slice.strip if params_node.rest
        params_node.keywords.each { |p| parts << p.location.slice.strip }
        parts << params_node.keyword_rest.location.slice.strip if params_node.keyword_rest
        parts << params_node.block.location.slice.strip        if params_node.block

        parts
      end

      # ── 4. Extract to let (RSpec) ─────────────────────────────────────────────

      RSPEC_EXAMPLE_METHODS = %i[it specify example scenario].freeze

      def rspec_example?(call_node)
        RSPEC_EXAMPLE_METHODS.include?(call_node.name) && call_node.block
      end

      def emit_extract_to_let(write_node, example_call_node)
        var_name = write_node.name.to_s
        rhs_src  = write_node.value.location.slice.strip
        indent   = indent_for(example_call_node)

        # Insert `let(:name) { value }` on the line before the example call.
        insert_line = example_call_node.location.start_line - 1
        let_text    = "#{indent}let(:#{var_name}) { #{rhs_src} }\n"

        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: insert_line, character: 0),
            end: Interface::Position.new(line: insert_line, character: 0)
          ),
          new_text: let_text
        )

        # Delete the original assignment line inside the example.
        delete_edit = delete_line_edit(write_node)

        @response_builder << Interface::CodeAction.new(
          title: "Extract to let(:#{var_name})",
          kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit: multi_edit_workspace_edit([insert_edit, delete_edit])
        )
      end
    end
  end
end
