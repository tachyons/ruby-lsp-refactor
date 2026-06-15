# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Emits a "Convert to interpolated string" code action when the cursor is
    # on a single-quoted StringNode.
    #
    # Input:   'hello world'
    # Output:  "hello world"
    #
    # The action only upgrades the delimiters; the developer can then type #{}
    # to add interpolation.  Backslash-escape sequences that are meaningful in
    # double-quoted strings but literal in single-quoted strings (e.g. \n, \t)
    # are left as-is — the developer is expected to review them.
    class StringListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_string_node_enter)
      end

      def on_string_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless single_quoted?(node)

        emit_convert_to_interpolated(node)
      rescue StandardError
        nil
      end

      private

      # Returns true when the string literal uses single-quote delimiters.
      def single_quoted?(node)
        node.opening_loc&.slice == "'"
      end

      def emit_convert_to_interpolated(node)
        # Escape any bare double-quotes inside the string content so the
        # resulting double-quoted literal remains valid.
        content  = node.unescaped.gsub('"', '\\"')
        new_text = "\"#{content}\""

        @response_builder << Interface::CodeAction.new(
          title: "Convert to interpolated string",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end
    end
  end
end
