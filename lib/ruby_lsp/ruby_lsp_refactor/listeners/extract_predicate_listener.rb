# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Extract predicate methods" when the cursor is on a compound
    # `&&` or `||` expression that is the sole statement in a method body.
    #
    # From "Refactor Compound Conditionals into Methods" in Refactoring Rails:
    # each operand becomes a private predicate method, making the condition
    # self-documenting and each predicate independently testable.
    #
    # Input (cursor on the compound expression):
    #   def eligible_for_return?
    #     expired_orders.exclude?(self) && self.value > MINIMUM_RETURN_VALUE
    #   end
    #
    # Output:
    #   def eligible_for_return?
    #     predicate_1? && predicate_2?
    #   end
    #
    #   private
    #
    #   def predicate_1?
    #     expired_orders.exclude?(self)
    #   end
    #
    #   def predicate_2?
    #     self.value > MINIMUM_RETURN_VALUE
    #   end
    #
    # The generated names `predicate_1?` / `predicate_2?` are intentional
    # placeholders — the developer renames them to reflect intent.
    class ExtractPredicateListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context
        @current_def      = nil

        dispatcher.register(
          self,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_and_node_enter,
          :on_or_node_enter
        )
      end

      def on_def_node_enter(node)
        @current_def = node
      rescue StandardError
        nil
      end

      def on_def_node_leave(_node)
        @current_def = nil
      rescue StandardError
        nil
      end

      def on_and_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless sole_statement_in_def?(node)

        emit_extract_predicates(node, "&&")
      rescue StandardError
        nil
      end

      def on_or_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless sole_statement_in_def?(node)

        emit_extract_predicates(node, "||")
      rescue StandardError
        nil
      end

      private

      # The compound expression must be the only statement in the method body
      # so the replacement is unambiguous.
      def sole_statement_in_def?(node)
        return false unless @current_def

        body = @current_def.body
        return false unless body.is_a?(Prism::StatementsNode)
        return false unless body.body.length == 1

        body.body.first.equal?(node)
      end

      def emit_extract_predicates(node, operator)
        def_node    = @current_def
        indent      = indent_for(def_node)
        body_indent = "#{indent}  "

        left_src  = node.left.location.slice.strip
        right_src = node.right.location.slice.strip

        # Replace the compound expression with calls to the two new predicates.
        replace_edit = Interface::TextEdit.new(
          range: node_to_lsp_range(node),
          new_text: "#{body_indent}predicate_1? #{operator} predicate_2?"
        )

        # Insert the two private predicate methods after the enclosing def.
        insert_line = def_node.location.end_line
        new_methods = "\n#{indent}private\n\n" \
                      "#{indent}def predicate_1?\n" \
                      "#{body_indent}#{left_src}\n" \
                      "#{indent}end\n\n" \
                      "#{indent}def predicate_2?\n" \
                      "#{body_indent}#{right_src}\n" \
                      "#{indent}end\n"

        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: insert_line, character: 0),
            end: Interface::Position.new(line: insert_line, character: 0)
          ),
          new_text: new_methods
        )

        @response_builder << Interface::CodeAction.new(
          title: "Extract predicate methods",
          kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit: multi_edit_workspace_edit([replace_edit, insert_edit])
        )
      end
    end
  end
end
