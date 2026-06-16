# frozen_string_literal: true

require "uri"
require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Extract to include file" when the cursor is on a ModuleNode or
    # ClassNode that coexists with other top-level statements in the same file.
    #
    # The action:
    #   1. Creates a new file named after the module/class (snake_case) in the
    #      same directory as the source file.
    #   2. Writes the extracted node's source into the new file, prefixed with
    #      the standard `# frozen_string_literal: true` magic comment.
    #   3. Replaces the extracted node in the source file with a
    #      `require_relative` statement.
    #
    # This uses `document_changes` (not `changes`) in the WorkspaceEdit so
    # that the LSP client can handle the CreateFile resource operation.
    #
    # Input (cursor on the module, file also contains User class):
    #   # app/models/user.rb
    #   module Greetable
    #     def greet = "hello"
    #   end
    #
    #   class User
    #     include Greetable
    #   end
    #
    # Output:
    #   # app/models/greetable.rb  (new file)
    #   # frozen_string_literal: true
    #
    #   module Greetable
    #     def greet = "hello"
    #   end
    #
    #   # app/models/user.rb  (modified)
    #   require_relative "greetable"
    #
    #   class User
    #     include Greetable
    #   end
    class ExtractIncludeFileListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder  = response_builder
        @node_context      = node_context
        @top_level_count   = 0

        dispatcher.register(
          self,
          :on_program_node_enter,
          :on_module_node_enter,
          :on_class_node_enter
        )
      end

      # Count top-level statements so we know whether extraction is meaningful.
      def on_program_node_enter(node)
        @top_level_count = node.statements.body.length
      rescue StandardError
        nil
      end

      def on_module_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless top_level_node?(node)
        return unless @top_level_count > 1

        emit_extract(node, module_name(node))
      rescue StandardError
        nil
      end

      def on_class_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless top_level_node?(node)
        return unless @top_level_count > 1

        emit_extract(node, class_name(node))
      rescue StandardError
        nil
      end

      private

      # A node is top-level when its start column is 0 (not nested inside
      # another class/module).
      def top_level_node?(node)
        node.location.start_column.zero?
      end

      def module_name(node)
        node.constant_path.location.slice
      end

      def class_name(node)
        node.constant_path.location.slice
      end

      def emit_extract(node, const_name)
        source_uri_str = @node_context.uri
        new_uri_str    = new_file_uri(source_uri_str, const_name)
        require_name   = snake_case(const_name)
        node_src       = node.location.slice

        # ── 1. Create the new file ──────────────────────────────────────────
        create_op = create_file_operation(new_uri_str)

        # ── 2. Write the extracted source into the new file ─────────────────
        new_file_content = "# frozen_string_literal: true\n\n#{node_src}\n"
        write_new_file   = text_document_edit(
          new_uri_str,
          [
            Interface::TextEdit.new(
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0)
              ),
              new_text: new_file_content
            )
          ]
        )

        # ── 3. Replace the node in the source file with require_relative ────
        # Include a trailing newline so the surrounding code stays clean.
        require_text   = "require_relative \"#{require_name}\"\n"
        replace_in_src = text_document_edit(
          source_uri_str,
          [
            Interface::TextEdit.new(
              range: node_to_lsp_range(node),
              new_text: require_text
            )
          ]
        )

        @response_builder << Interface::CodeAction.new(
          title: "Extract to include file \"#{require_name}.rb\"",
          kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
          edit: multi_file_workspace_edit([create_op, write_new_file, replace_in_src])
        )
      end

      # Derives the URI for the new file from the source file's URI and the
      # constant name.  The new file is placed in the same directory.
      def new_file_uri(source_uri_str, const_name)
        filename   = "#{snake_case(const_name)}.rb"
        source_uri = URI(source_uri_str)
        source_dir = File.dirname(source_uri.path)
        new_path   = File.join(source_dir, filename)

        new_uri      = source_uri.dup
        new_uri.path = new_path
        new_uri.to_s
      end

      # Converts CamelCase to snake_case.
      def snake_case(name)
        name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end
    end
  end
end
