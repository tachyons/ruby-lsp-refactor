# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Toggles between `let` and `let!` on RSpec lazy/eager memoization helpers.
    #
    # Emitted actions
    # ───────────────
    # 1. Convert let → let!
    #      let(:user) { User.new }   →   let!(:user) { User.new }
    #
    # 2. Convert let! → let
    #      let!(:user) { User.new }  →   let(:user) { User.new }
    class RspecLetListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless let_call?(node)

        if node.name == :let
          emit_toggle(node, "let", "let!")
        else
          emit_toggle(node, "let!", "let")
        end
      rescue StandardError
        nil
      end

      private

      def let_call?(node)
        %i[let let!].include?(node.name) &&
          node.block.is_a?(Prism::BlockNode) &&
          node.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
      end

      def emit_toggle(node, from_kw, to_kw)
        # Replace only the method name portion, preserving arguments and block.
        src      = node.location.slice
        new_text = "#{indent_for(node)}#{src.sub(/\A(\s*)#{Regexp.escape(from_kw)}/, "\\1#{to_kw}")}"

        @response_builder << Interface::CodeAction.new(
          title: "Convert #{from_kw} to #{to_kw}",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end
    end
  end
end
