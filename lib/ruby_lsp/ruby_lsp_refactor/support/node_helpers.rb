# frozen_string_literal: true

module RubyLsp
  module Refactor
    module Support
      # Shared helpers mixed into every listener.
      #
      # Provides:
      #   - node_to_lsp_range(node)       – Prism location → Interface::Range
      #   - node_covers_cursor?(node)      – overlap check against @node_context.range
      #   - single_edit_workspace_edit(…)  – convenience WorkspaceEdit factory
      module NodeHelpers
        # Converts a Prism node's location to an LSP Interface::Range.
        #
        # @param node [Prism::Node]
        # @return [Interface::Range]
        def node_to_lsp_range(node)
          loc = node.location
          Interface::Range.new(
            start: Interface::Position.new(
              line:      loc.start_line - 1,
              character: loc.start_column,
            ),
            end: Interface::Position.new(
              line:      loc.end_line - 1,
              character: loc.end_column,
            ),
          )
        end

        # Returns true when the node's source range overlaps the cursor/selection
        # range provided by the LSP client via @node_context.
        #
        # @param node [Prism::Node]
        # @return [Boolean]
        def node_covers_cursor?(node)
          cursor = @node_context.range
          return true unless cursor

          node_start = node.location.start_line - 1
          node_end   = node.location.end_line   - 1

          cursor_start = cursor.start.line
          cursor_end   = cursor.end.line

          node_start <= cursor_end && node_end >= cursor_start
        end

        # Builds a WorkspaceEdit containing a single TextEdit that replaces the
        # entire range of +node+ with +new_text+.
        #
        # @param node     [Prism::Node]
        # @param new_text [String]
        # @return [Interface::WorkspaceEdit]
        def single_edit_workspace_edit(node, new_text)
          Interface::WorkspaceEdit.new(
            changes: {
              @node_context.uri => [
                Interface::TextEdit.new(range: node_to_lsp_range(node), new_text: new_text),
              ],
            },
          )
        end

        # Builds a WorkspaceEdit from an arbitrary array of TextEdit objects.
        #
        # @param edits [Array<Interface::TextEdit>]
        # @return [Interface::WorkspaceEdit]
        def multi_edit_workspace_edit(edits)
          Interface::WorkspaceEdit.new(
            changes: { @node_context.uri => edits },
          )
        end

        # Produces a TextEdit that deletes the full source line of +node+,
        # including its trailing newline so no blank line is left behind.
        #
        # @param node [Prism::Node]
        # @return [Interface::TextEdit]
        def delete_line_edit(node)
          line = node.location.start_line - 1
          Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: line,     character: 0),
              end:   Interface::Position.new(line: line + 1, character: 0),
            ),
            new_text: "",
          )
        end

        # Leading whitespace for the line that contains +node+.
        #
        # @param node [Prism::Node]
        # @return [String]
        def indent_for(node)
          " " * node.location.start_column
        end
      end
    end
  end
end
