# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Convert to early return" when the cursor is on a guard `if` block
    # that is the first statement in a method body and has no `else` branch.
    #
    # From "Prefer early returns" in Refactoring Rails: replace a top-level
    # guard `if` with `return unless` so the happy path is not nested.
    #
    # Input (cursor on the `if` line):
    #   def charge_purchase(order)
    #     if order.fulfilled?
    #       OrderChargeConfirmation.new(order).create!
    #     end
    #   end
    #
    # Output:
    #   def charge_purchase(order)
    #     return unless order.fulfilled?
    #     OrderChargeConfirmation.new(order).create!
    #   end
    #
    # Eligibility:
    #   - Block-form `if` (has end_keyword_loc) with no else/elsif.
    #   - Must be the first statement in the enclosing method body.
    #   - Body may contain one or more statements.
    class EarlyReturnListener
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
          :on_if_node_enter
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

      def on_if_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless eligible?(node)

        emit_early_return(node)
      rescue StandardError
        nil
      end

      private

      def eligible?(node)
        return false unless node.end_keyword_loc # block-form only
        return false if node.subsequent # no else/elsif
        return false unless node.statements&.body&.any?
        return false unless first_statement_in_def?(node)

        true
      end

      def first_statement_in_def?(if_node)
        return false unless @current_def

        body = @current_def.body
        return false unless body.is_a?(Prism::StatementsNode)

        body.body.first.equal?(if_node)
      end

      def emit_early_return(node)
        indent     = indent_for(node)
        cond_src   = node.predicate.location.slice.strip
        body_lines = node.statements.body
                         .map { |s| "#{indent}#{s.location.slice.strip}" }
                         .join("\n")

        new_text = "#{indent}return unless #{cond_src}\n#{body_lines}"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to early return",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end
    end
  end
end
