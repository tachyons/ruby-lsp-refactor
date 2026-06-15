# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Converts a bracket array of plain string literals into a %w[] word array,
    # and vice-versa.
    #
    # Emitted actions
    # ───────────────
    # 1. Convert to string array (%w[])
    #      ["foo", "bar", "baz"]   →   %w[foo bar baz]
    #
    # 2. Convert to bracket array
    #      %w[foo bar baz]         →   ["foo", "bar", "baz"]
    #
    # Only plain string literals with no interpolation and no spaces in their
    # content are eligible for compression into %w[].
    class StringArrayListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_array_node_enter)
      end

      def on_array_node_enter(node)
        return unless node_covers_cursor?(node)
        return if node.elements.empty?

        if bracket_string_array?(node)
          emit_to_percent_w(node)
        elsif percent_w_array?(node)
          emit_to_bracket(node)
        end
      rescue StandardError
        nil
      end

      private

      # Returns true when every element is a plain double-quoted StringNode
      # with no interpolation and no spaces in its content.
      def bracket_string_array?(node)
        return false unless node.opening_loc&.slice == "["

        node.elements.all? do |el|
          el.is_a?(Prism::StringNode) &&
            el.opening_loc&.slice == '"' &&
            !el.unescaped.include?(" ") &&
            !el.unescaped.include?("\t")
        end
      end

      # Returns true when the array uses %w[] or %W[] syntax.
      def percent_w_array?(node)
        opening = node.opening_loc&.slice.to_s
        opening.start_with?("%w", "%W")
      end

      def emit_to_percent_w(node)
        words    = node.elements.map(&:unescaped)
        new_text = "%w[#{words.join(" ")}]"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to string array (%w[])",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end

      def emit_to_bracket(node)
        words    = node.elements.map { |el| "\"#{el.unescaped}\"" }
        new_text = "[#{words.join(", ")}]"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to bracket array",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(node, new_text)
        )
      end
    end
  end
end
