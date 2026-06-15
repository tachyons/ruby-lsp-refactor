# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Wrap in freeze" on any unfrozen string literal, and
    # "Remove freeze" on a string that already calls .freeze.
    #
    # Emitted actions
    # ───────────────
    # 1. Wrap in freeze
    #      "hello"          →   "hello".freeze
    #
    # 2. Remove freeze
    #      "hello".freeze   →   "hello"
    class StringFreezeListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        # Track start offsets of string nodes that are already receivers of
        # .freeze so on_string_node_enter can skip them.  Populated during
        # on_call_node_enter which fires for the outer CallNode first.
        @frozen_string_offsets = {}

        dispatcher.register(self, :on_call_node_enter, :on_string_node_enter)
      end

      # Fires for every CallNode — including `.freeze` calls.
      # We register this before on_string_node_enter so the offset set is
      # populated before the inner StringNode callback fires.
      def on_call_node_enter(node)
        return unless node.name == :freeze
        return unless node.receiver.is_a?(Prism::StringNode)
        return unless node.arguments.nil?

        # Mark the receiver string so on_string_node_enter skips it.
        @frozen_string_offsets[node.receiver.location.start_offset] = true

        return unless node_covers_cursor?(node)

        emit_remove_freeze(node)
      rescue StandardError
        nil
      end

      # Offer "Wrap in freeze" for plain string literals that are not already
      # the receiver of a .freeze call.
      def on_string_node_enter(node)
        return unless node_covers_cursor?(node)
        return if @frozen_string_offsets.key?(node.location.start_offset)

        emit_wrap_freeze(node)
      rescue StandardError
        nil
      end

      private

      def emit_wrap_freeze(node)
        str_src  = node.location.slice
        new_text = "#{str_src}.freeze"

        @response_builder << Interface::CodeAction.new(
          title: "Wrap in freeze",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end

      def emit_remove_freeze(node)
        str_src = node.receiver.location.slice

        @response_builder << Interface::CodeAction.new(
          title: "Remove freeze",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, str_src)
        )
      end
    end
  end
end
