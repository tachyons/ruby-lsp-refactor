# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Implements the "Pull Up Method" refactoring (ruby-lsp issue #2502).
    #
    # Moves a method from a child class to its parent class. The action is
    # offered when the cursor is on a DefNode inside a ClassNode that declares
    # a superclass.
    #
    # Two cases are handled:
    #
    # 1. Same-file — parent class is defined in the same document.
    #    A single WorkspaceEdit with two TextEdits is produced:
    #      a. Insert the method (re-indented) before the parent's `end`.
    #      b. Delete the method (and its surrounding blank line) from the child.
    #
    # 2. Cross-file — parent class is defined in a different file, located via
    #    the ruby-lsp index.
    #    A WorkspaceEdit with document_changes is produced:
    #      a. TextDocumentEdit on the parent file — insert the method.
    #      b. TextDocumentEdit on the child file  — delete the method.
    #
    # Example:
    #   # Before (cursor on `def foo`)
    #   class Parent
    #   end
    #
    #   class Child < Parent
    #     def foo
    #       "hello"
    #     end
    #   end
    #
    #   # After
    #   class Parent
    #     def foo
    #       "hello"
    #     end
    #   end
    #
    #   class Child < Parent
    #   end
    class PullUpMethodListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher, document, global_state = nil)
        @response_builder = response_builder
        @node_context     = node_context
        @document         = document
        @global_state     = global_state

        # Stack of enclosing ClassNodes so we know which class owns the cursor.
        @class_stack = []

        # All ClassNodes in the file keyed by constant name, for same-file lookup.
        @classes_in_file = {}

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_def_node_enter
        )
      end

      def on_class_node_enter(node)
        name = node.constant_path.location.slice
        @classes_in_file[name] ||= []
        @classes_in_file[name] << node
        @class_stack.push(node)
      rescue StandardError
        nil
      end

      def on_class_node_leave(_node)
        @class_stack.pop
      rescue StandardError
        nil
      end

      def on_def_node_enter(node)
        return unless node_covers_cursor?(node)

        enclosing_class = @class_stack.last
        return unless enclosing_class
        return unless enclosing_class.superclass

        superclass_name = enclosing_class.superclass.location.slice
        emit_pull_up(node, enclosing_class, superclass_name)
      rescue StandardError
        nil
      end

      private

      def emit_pull_up(def_node, child_class, superclass_name)
        # Try same-file first.
        parent_nodes = @classes_in_file[superclass_name]

        if parent_nodes&.any?
          # Use the last definition in the file (handles re-openings).
          parent_node = parent_nodes.last
          emit_same_file_pull_up(def_node, child_class, parent_node)
        else
          emit_cross_file_pull_up(def_node, child_class, superclass_name)
        end
      end

      # ── same-file ─────────────────────────────────────────────────────────────

      def emit_same_file_pull_up(def_node, _child_class, parent_node)
        source_lines = @document.source.lines

        insert_edit = build_insert_edit(def_node, parent_node, source_lines)
        delete_edit = build_delete_edit(def_node, source_lines)

        @response_builder << Interface::CodeAction.new(
          title: "Pull up method '#{def_node.name}' to #{parent_node.constant_path.location.slice}",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_edit_workspace_edit([insert_edit, delete_edit])
        )
      end

      # ── cross-file ────────────────────────────────────────────────────────────

      def emit_cross_file_pull_up(def_node, _child_class, superclass_name)
        return unless @global_state

        index = @global_state.index
        return unless index

        # Look up the superclass in the index.
        # index[] returns an array of Entry objects or nil.
        entries = index[superclass_name]
        return unless entries&.any?

        # Prefer an entry whose file is already the current document (re-opening
        # in the same file was already handled by the same-file path, so this
        # picks the best cross-file candidate). Fall back to the first entry.
        current_path = URI(@node_context.uri).path
        entry = entries.find { |e| e.file_path != current_path } || entries.first

        return unless entry&.file_path
        return unless File.exist?(entry.file_path)

        parent_file_uri = entry.uri.to_s

        # The index Location uses 1-based lines.
        # end_line points to the line containing the class's `end` keyword.
        parent_end_line_0based  = entry.location.end_line - 1 # 0-based
        parent_class_column     = entry.location.start_column

        child_source_lines = @document.source.lines
        method_text        = re_indented_method(def_node, child_source_lines, parent_class_column)
        delete_edit        = build_delete_edit(def_node, child_source_lines)

        insert_edit = Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: parent_end_line_0based, character: 0),
            end: Interface::Position.new(line: parent_end_line_0based, character: 0)
          ),
          new_text: method_text
        )

        insert_doc_edit = text_document_edit(parent_file_uri, [insert_edit])
        delete_doc_edit = text_document_edit(@node_context.uri, [delete_edit])

        @response_builder << Interface::CodeAction.new(
          title: "Pull up method '#{def_node.name}' to #{superclass_name} (#{File.basename(entry.file_path)})",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_file_workspace_edit([insert_doc_edit, delete_doc_edit])
        )
      rescue StandardError
        nil
      end

      # ── edit builders ─────────────────────────────────────────────────────────

      # Builds a TextEdit that inserts the method before the parent class's `end`.
      def build_insert_edit(def_node, parent_node, source_lines)
        # end_keyword_loc.start_line is 1-based; the `end` line in 0-based terms.
        parent_end_line_0based = parent_node.end_keyword_loc.start_line - 1
        parent_col             = parent_node.location.start_column
        method_text            = re_indented_method(def_node, source_lines, parent_col)

        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: parent_end_line_0based, character: 0),
            end: Interface::Position.new(line: parent_end_line_0based, character: 0)
          ),
          new_text: method_text
        )
      end

      # Builds a TextEdit that deletes the method from the child class,
      # absorbing one surrounding blank line to keep spacing clean.
      def build_delete_edit(def_node, source_lines)
        delete_start = def_node.location.start_line - 1  # 0-based
        delete_end   = def_node.location.end_line        # 0-based exclusive

        # Absorb the blank line before the method if present; otherwise the one after.
        if delete_start.positive? && source_lines[delete_start - 1]&.strip&.empty?
          delete_start -= 1
        elsif source_lines[delete_end]&.strip&.empty?
          delete_end += 1
        end

        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: delete_start, character: 0),
            end: Interface::Position.new(line: delete_end, character: 0)
          ),
          new_text: ""
        )
      end

      # Returns the method source re-indented for the parent class body,
      # wrapped in blank lines so the parent's `end` stays on its own line.
      def re_indented_method(def_node, source_lines, parent_class_column)
        method_lines  = source_lines[(def_node.location.start_line - 1)..(def_node.location.end_line - 1)]
        child_indent  = " " * def_node.location.start_column
        parent_indent = " " * (parent_class_column + 2)

        re_indented = method_lines.map do |line|
          if line.start_with?(child_indent)
            parent_indent + line[child_indent.length..]
          else
            line
          end
        end.join

        "\n#{re_indented}\n"
      end
    end
  end
end
