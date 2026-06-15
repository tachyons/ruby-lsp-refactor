# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Extract constant" when the cursor is on a literal value
    # (Integer, Float, String, Symbol) inside a class or module body.
    #
    # The new constant is inserted at the top of the enclosing class/module
    # body, and the literal is replaced with the constant name.
    #
    # Input (cursor on `100`):
    #   class Processor
    #     def run
    #       items.first(100)
    #     end
    #   end
    #
    # Output:
    #   class Processor
    #     EXTRACTED_CONSTANT = 100
    #
    #     def run
    #       items.first(EXTRACTED_CONSTANT)
    #     end
    #   end
    class ConstantListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      LITERAL_NODE_TYPES = [
        Prism::IntegerNode,
        Prism::FloatNode,
        Prism::StringNode,
        Prism::SymbolNode
      ].freeze

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        # Track the nearest enclosing class/module so we know where to insert.
        @class_stack = []

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_integer_node_enter,
          :on_float_node_enter,
          :on_string_node_enter,
          :on_symbol_node_enter
        )
      end

      def on_class_node_enter(node)  = @class_stack.push(node)
      def on_class_node_leave(_node) = @class_stack.pop
      def on_module_node_enter(node)  = @class_stack.push(node)
      def on_module_node_leave(_node) = @class_stack.pop

      def on_integer_node_enter(node) = maybe_emit(node)
      def on_float_node_enter(node)   = maybe_emit(node)
      def on_string_node_enter(node)  = maybe_emit(node)
      def on_symbol_node_enter(node)  = maybe_emit(node)

      private

      def maybe_emit(node)
        return unless node_covers_cursor?(node)
        return if @class_stack.empty?

        # Don't offer on constant assignments themselves.
        enclosing = @class_stack.last
        return unless enclosing

        emit_extract_constant(node, enclosing)
      rescue StandardError
        nil
      end

      def emit_extract_constant(literal_node, class_node)
        literal_src = literal_node.location.slice.strip
        indent      = indent_for(class_node)
        body_indent = "#{indent}  "

        # Insert the constant declaration at the top of the class body.
        # The class body starts on the line after the class declaration.
        body_start_line = class_node.body&.location&.start_line
        return unless body_start_line

        insert_line = body_start_line - 1
        const_decl  = "#{body_indent}EXTRACTED_CONSTANT = #{literal_src}\n\n"

        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: insert_line, character: 0),
            end: Interface::Position.new(line: insert_line, character: 0)
          ),
          new_text: const_decl
        )

        replace_edit = Interface::TextEdit.new(
          range: node_to_lsp_range(literal_node),
          new_text: "EXTRACTED_CONSTANT"
        )

        @response_builder << Interface::CodeAction.new(
          title: "Extract constant",
          kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit: multi_edit_workspace_edit([insert_edit, replace_edit])
        )
      end
    end
  end
end
