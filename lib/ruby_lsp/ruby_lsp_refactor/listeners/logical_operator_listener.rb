# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Toggles between symbolic and word forms of logical operators.
    #
    # Emitted actions
    # ───────────────
    # AndNode:
    #   user.valid? && user.save   →   user.valid? and user.save
    #   user.valid? and user.save  →   user.valid? && user.save
    #
    # OrNode:
    #   a || b   →   a or b
    #   a or b   →   a || b
    class LogicalOperatorListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_and_node_enter, :on_or_node_enter)
      end

      def on_and_node_enter(node)
        return unless node_covers_cursor?(node)

        if node.operator_loc.slice == "&&"
          emit_toggle(node, "&&", "and")
        else
          emit_toggle(node, "and", "&&")
        end
      rescue StandardError
        nil
      end

      def on_or_node_enter(node)
        return unless node_covers_cursor?(node)

        if node.operator_loc.slice == "||"
          emit_toggle(node, "||", "or")
        else
          emit_toggle(node, "or", "||")
        end
      rescue StandardError
        nil
      end

      private

      def emit_toggle(node, from_op, to_op)
        left_src  = node.left.location.slice.strip
        right_src = node.right.location.slice.strip
        new_text  = "#{indent_for(node)}#{left_src} #{to_op} #{right_src}"

        title = "Convert '#{from_op}' to '#{to_op}'"

        @response_builder << Interface::CodeAction.new(
          title: title,
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end
    end
  end
end
