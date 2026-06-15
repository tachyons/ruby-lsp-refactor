# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Detects an `attr_reader :name` paired with a canonical manual writer
    # `def name=(val); @name = val; end` in the same class body and offers
    # to collapse them into a single `attr_accessor :name`.
    #
    # Input (cursor on either the attr_reader or the writer def):
    #   attr_reader :name
    #   def name=(val)
    #     @name = val
    #   end
    #
    # Output:
    #   attr_accessor :name
    #
    # The manual writer is considered canonical when its body contains exactly
    # one statement of the form `@name = val` where `val` is the sole parameter.
    class AccessorListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        # Collect attr_reader calls and writer defs within the same class body.
        @attr_readers = []  # [{ name:, node: }]
        @writer_defs  = []  # [{ name:, node: }]
        @class_depth  = 0

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_call_node_enter,
          :on_def_node_enter
        )
      end

      def on_class_node_enter(_node)
        @class_depth += 1
      end

      def on_class_node_leave(_node)
        @class_depth -= 1
        # Emit any matched pairs before clearing — on_program_node_leave fires
        # after on_class_node_leave, so we must act here while data is present.
        emit_matching_pairs
        @attr_readers.clear
        @writer_defs.clear
      end

      def on_call_node_enter(node)
        return unless @class_depth.positive?
        return unless node.name == :attr_reader
        return unless node.arguments

        node.arguments.arguments.each do |arg|
          next unless arg.is_a?(Prism::SymbolNode)

          @attr_readers << { name: arg.unescaped.to_sym, node: node, sym_node: arg }
        end
      rescue StandardError
        nil
      end

      def on_def_node_enter(node)
        return unless @class_depth.positive?
        return unless node.name.to_s.end_with?("=")

        attr_name = node.name.to_s.delete_suffix("=").to_sym
        return unless canonical_writer?(node, attr_name)

        @writer_defs << { name: attr_name, node: node }
      rescue StandardError
        nil
      end

      private

      # Match readers with writers and emit actions for any pair where the
      # cursor falls on either node.
      def emit_matching_pairs
        @attr_readers.each do |reader|
          writer = @writer_defs.find { |w| w[:name] == reader[:name] }
          next unless writer

          next unless node_covers_cursor?(reader[:node]) ||
                      node_covers_cursor?(writer[:node])

          emit_collapse(reader, writer)
        end
      rescue StandardError
        nil
      end

      # A writer def is canonical when:
      #   1. It has exactly one required parameter.
      #   2. Its body is exactly one statement: `@name = <param>`.
      def canonical_writer?(def_node, attr_name)
        params = def_node.parameters&.requireds
        return false unless params&.length == 1

        param_name = params.first.name
        body_stmts = def_node.body&.body
        return false unless body_stmts&.length == 1

        stmt = body_stmts.first
        return false unless stmt.is_a?(Prism::InstanceVariableWriteNode)
        return false unless stmt.name.to_s == "@#{attr_name}"
        return false unless stmt.value.is_a?(Prism::LocalVariableReadNode)
        return false unless stmt.value.name == param_name

        true
      end

      def emit_collapse(reader, writer)
        reader_node = reader[:node]
        writer_node = writer[:node]
        attr_name   = reader[:name]

        # Replace the attr_reader line with attr_accessor.
        # The sym_node is the :name argument; we keep the same symbol.
        reader_src = reader_node.location.slice
        new_reader = reader_src.sub("attr_reader", "attr_accessor")

        replace_reader = Interface::TextEdit.new(
          range: node_to_lsp_range(reader_node),
          new_text: new_reader
        )

        # Delete the entire writer def (all its lines).
        writer_start_line = writer_node.location.start_line - 1
        writer_end_line   = writer_node.location.end_line

        delete_writer = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: writer_start_line, character: 0),
            end: Interface::Position.new(line: writer_end_line, character: 0)
          ),
          new_text: ""
        )

        @response_builder << Interface::CodeAction.new(
          title: "Convert to attr_accessor :#{attr_name}",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_edit_workspace_edit([replace_reader, delete_writer])
        )
      end
    end
  end
end
