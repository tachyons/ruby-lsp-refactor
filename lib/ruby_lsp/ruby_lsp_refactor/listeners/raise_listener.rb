# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Simplifies redundant RuntimeError raises.
    #
    # Emitted actions
    # ───────────────
    # 1. Simplify raise
    #      raise RuntimeError, "msg"   →   raise "msg"
    #      fail  RuntimeError, "msg"   →   fail  "msg"
    #
    # RuntimeError is Ruby's default exception class; passing it explicitly
    # is redundant.  Only the two-argument form (class, message) is handled —
    # `raise RuntimeError.new("msg")` is left alone because the intent may be
    # to call a custom initializer.
    class RaiseListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless raise_or_fail?(node)
        return unless redundant_runtime_error?(node)

        emit_simplify_raise(node)
      rescue StandardError
        nil
      end

      private

      def raise_or_fail?(node)
        %i[raise fail].include?(node.name)
      end

      # Returns true when the call is `raise RuntimeError, <message>` —
      # exactly two arguments where the first is the constant RuntimeError.
      def redundant_runtime_error?(node)
        args = node.arguments&.arguments
        return false unless args&.length == 2

        first = args[0]
        first.is_a?(Prism::ConstantReadNode) && first.name == :RuntimeError
      end

      def emit_simplify_raise(node)
        keyword  = node.name.to_s # "raise" or "fail"
        msg_src  = node.arguments.arguments[1].location.slice.strip
        indent   = indent_for(node)
        new_text = "#{indent}#{keyword} #{msg_src}"

        @response_builder << Interface::CodeAction.new(
          title: "Simplify raise (remove redundant RuntimeError)",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end
    end
  end
end
