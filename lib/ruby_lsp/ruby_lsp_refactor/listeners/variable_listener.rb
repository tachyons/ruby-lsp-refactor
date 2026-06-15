# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Handles variable-related code actions.
    #
    # Emitted actions
    # ───────────────
    # 1. Inline variable
    #      result = user.calculate   →  (line deleted)
    #      puts result               →  puts user.calculate
    #
    # 2. Extract local variable
    #      Cursor on any expression; wraps it in a new variable assignment
    #      inserted on the line above.
    #      user.full_name.upcase     →  name = user.full_name.upcase
    #                                   name
    class VariableListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        # Collect all read nodes keyed by variable name so we can cross-reference
        # them when we encounter a matching write node.
        @read_nodes = Hash.new { |h, k| h[k] = [] } # { name => [ReadNode, ...] }

        # Defer inline-variable actions until after the full walk so that all
        # read nodes are collected before we build the edits.
        @pending_write_nodes = []

        dispatcher.register(
          self,
          :on_local_variable_write_node_enter,
          :on_local_variable_read_node_enter,
          :on_call_node_enter,
          :on_program_node_leave,
        )
      end

      # ── dispatcher callbacks ────────────────────────────────────────────────

      def on_local_variable_read_node_enter(node)
        @read_nodes[node.name] << node
      rescue StandardError
        nil
      end

      def on_local_variable_write_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless node.value

        # Defer: we need all reads collected before building the edit.
        @pending_write_nodes << node
      rescue StandardError
        nil
      end

      # Offer "Extract local variable" for any call expression under the cursor.
      def on_call_node_enter(node)
        return unless node_covers_cursor?(node)

        emit_extract_local_variable(node)
      rescue StandardError
        nil
      end

      # After the full AST walk, all read nodes are known — emit inline actions.
      def on_program_node_leave(_node)
        @pending_write_nodes.each { |w| emit_inline_variable(w) }
      rescue StandardError
        nil
      end

      private

      # ── inline variable ─────────────────────────────────────────────────────

      def emit_inline_variable(write_node)
        rhs_text = write_node.value.location.slice.strip
        edits    = [delete_line_edit(write_node)]

        @read_nodes[write_node.name].each do |read_node|
          edits << Interface::TextEdit.new(
            range:    node_to_lsp_range(read_node),
            new_text: rhs_text,
          )
        end

        @response_builder << Interface::CodeAction.new(
          title: "Inline variable '#{write_node.name}'",
          kind:  Constant::CodeActionKind::REFACTOR_INLINE,
          edit:  multi_edit_workspace_edit(edits),
        )
      end

      # ── extract local variable ───────────────────────────────────────────────

      def emit_extract_local_variable(node)
        expr_src   = node.location.slice.strip
        indent     = " " * node.location.start_column
        insert_line = node.location.start_line - 1

        # Insert `variable = <expr>` on the line above, then replace the
        # expression in-place with the variable name.
        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: insert_line, character: 0),
            end:   Interface::Position.new(line: insert_line, character: 0),
          ),
          new_text: "#{indent}variable = #{expr_src}\n",
        )

        replace_edit = Interface::TextEdit.new(
          range:    node_to_lsp_range(node),
          new_text: "variable",
        )

        @response_builder << Interface::CodeAction.new(
          title: "Extract local variable",
          kind:  Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit:  multi_edit_workspace_edit([insert_edit, replace_edit]),
        )
      end
    end
  end
end
