# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Emits a "Convert to symbol array" code action when the cursor is on an
    # ArrayNode whose every element is a plain SymbolNode.
    #
    # Input:   [:foo, :bar, :baz]
    # Output:  %i[foo bar baz]
    #
    # Arrays that already use %i[] or %I[] syntax, or that contain non-symbol
    # elements, are ignored.
    class ArrayListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_array_node_enter)
      end

      def on_array_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless convertible_to_symbol_array?(node)

        emit_convert_to_symbol_array(node)
      rescue StandardError
        nil
      end

      private

      # Returns true when:
      #   1. The array uses bracket syntax (not already %i[] / %I[]).
      #   2. Every element is a plain colon-prefixed SymbolNode.
      #   3. There is at least one element.
      def convertible_to_symbol_array?(node)
        return false if node.elements.empty?
        return false unless node.opening_loc&.slice == "["

        node.elements.all? do |el|
          el.is_a?(Prism::SymbolNode) && el.opening_loc&.slice == ":"
        end
      end

      def emit_convert_to_symbol_array(node)
        symbols  = node.elements.map(&:unescaped)
        new_text = "%i[#{symbols.join(" ")}]"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to symbol array",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end
    end
  end
end
