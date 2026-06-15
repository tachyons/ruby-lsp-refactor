# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Detects common Enumerable method-chain patterns and offers a single
    # collapsed replacement.
    #
    # Emitted actions
    # ───────────────
    # 1. map + flatten(1) / flatten  →  flat_map
    #      items.map { |i| i.tags }.flatten(1)  →  items.flat_map { |i| i.tags }
    #
    # 2. select + first  →  find
    #      users.select { |u| u.admin? }.first  →  users.find { |u| u.admin? }
    #
    # 3. map + compact  →  filter_map
    #      items.map { |i| i.value }.compact  →  items.filter_map { |i| i.value }
    #
    # All three patterns share the same structure:
    #   outer_call( receiver: inner_call( block: BlockNode ) )
    # where outer_call has no block of its own.
    class EnumerableListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # { outer_method => { inner_method => replacement } }
      PATTERNS = {
        flatten: { map: "flat_map" },
        first: { select: "find" },
        compact: { map: "filter_map" }
      }.freeze

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless node_covers_cursor?(node)
        return if node.block # outer call must not have its own block

        outer_name = node.name
        return unless PATTERNS.key?(outer_name)

        # flatten is only eligible when called with no args or with arg `1`.
        return if outer_name == :flatten && !flatten_eligible?(node)

        inner = node.receiver
        return unless inner.is_a?(Prism::CallNode) && inner.block.is_a?(Prism::BlockNode)

        replacement = PATTERNS[outer_name][inner.name]
        return unless replacement

        emit_collapse(node, inner, replacement)
      rescue StandardError
        nil
      end

      private

      # flatten() and flatten(1) are eligible; flatten(2+) changes semantics.
      def flatten_eligible?(node)
        args = node.arguments&.arguments
        return true if args.nil? || args.empty?
        return true if args.length == 1 && args.first.is_a?(Prism::IntegerNode) &&
                       args.first.location.slice == "1"

        false
      end

      def emit_collapse(outer_node, inner_node, replacement)
        # Reconstruct: <receiver>.<replacement> <block>
        receiver_src = inner_node.receiver.location.slice.strip
        block_src    = inner_node.block.location.slice.strip

        new_text = "#{indent_for(outer_node)}#{receiver_src}.#{replacement} #{block_src}"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to .#{replacement}",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(outer_node, new_text)
        )
      end
    end
  end
end
