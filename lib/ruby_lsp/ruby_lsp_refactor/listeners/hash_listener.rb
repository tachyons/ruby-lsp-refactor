# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Emits a "Convert to keyword syntax" code action when the cursor is on a
    # HashNode (or a keyword-argument hash) that contains at least one
    # hash-rocket pair whose key is a simple symbol.
    #
    # Input:   { :foo => 1, :bar => "x" }
    # Output:  { foo: 1, bar: "x" }
    #
    # Pairs whose key is NOT a plain symbol (e.g. string keys, computed keys,
    # or keys that are already in keyword syntax) are left unchanged.
    class HashListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_hash_node_enter, :on_keyword_hash_node_enter)
      end

      def on_hash_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless has_rocket_pairs?(node.elements)

        emit_convert_hash(node, node.elements)
      rescue StandardError
        nil
      end

      # keyword_hash_node appears in method call arguments: foo(:a => 1)
      def on_keyword_hash_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless has_rocket_pairs?(node.elements)

        emit_convert_hash(node, node.elements)
      rescue StandardError
        nil
      end

      private

      # Returns true when at least one AssocNode uses a hash-rocket operator
      # and has a plain SymbolNode key.
      def has_rocket_pairs?(elements)
        elements.any? { |el| rocket_assoc?(el) }
      end

      # An AssocNode is a rocket pair when it has an operator_loc (the `=>`).
      def rocket_assoc?(el)
        el.is_a?(Prism::AssocNode) &&
          el.operator_loc &&
          el.key.is_a?(Prism::SymbolNode) &&
          el.key.opening_loc&.slice == ":"
      end

      def emit_convert_hash(node, elements)
        new_pairs = elements.map { |el| convert_element(el) }

        # Reconstruct the hash preserving the outer braces when present.
        # HashNode has opening/closing braces; KeywordHashNode does not.
        if node.is_a?(Prism::HashNode)
          new_text = "{ #{new_pairs.join(", ")} }"
        else
          new_text = new_pairs.join(", ")
        end

        @response_builder << Interface::CodeAction.new(
          title: "Convert to keyword syntax",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # Converts a single hash element to its string representation.
      # Rocket pairs with symbol keys become `key: value`; everything else
      # is reproduced verbatim from the source.
      def convert_element(el)
        if rocket_assoc?(el)
          key_name  = el.key.unescaped
          value_src = el.value.location.slice.strip
          "#{key_name}: #{value_src}"
        else
          el.location.slice.strip
        end
      end
    end
  end
end
