# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class ExtractIncludeFileListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      # ── core acceptance ────────────────────────────────────────────────────

      def test_extracts_module_to_new_file
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end

          class User
            include Greetable
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /Extract to include file/)
        refute_nil action

        assert_match(/greetable\.rb/, action.title)

        doc_changes = action.edit.document_changes
        assert_equal 3, doc_changes.length,
                     "Expected CreateFile + 2 TextDocumentEdits, got #{doc_changes.length}"
      end

      def test_create_file_operation_is_first
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end

          class User; end
        RUBY

        actions    = code_actions_for(source, line: 0)
        action     = find_action(actions, /Extract to include file/)
        refute_nil action

        create_op = action.edit.document_changes.first
        assert_equal "create", create_op.kind
        assert_match(/greetable\.rb/, create_op.uri)
      end

      def test_new_file_content_includes_frozen_comment_and_source
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end

          class User; end
        RUBY

        actions    = code_actions_for(source, line: 0)
        action     = find_action(actions, /Extract to include file/)
        refute_nil action

        # Second document_change is the TextDocumentEdit writing the new file.
        write_edit = action.edit.document_changes[1]
        content    = write_edit.edits.first.new_text

        assert_match(/# frozen_string_literal: true/, content)
        assert_match(/module Greetable/, content)
        assert_match(/def greet = "hello"/, content)
      end

      def test_source_file_is_replaced_with_require_relative
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end

          class User; end
        RUBY

        actions    = code_actions_for(source, line: 0)
        action     = find_action(actions, /Extract to include file/)
        refute_nil action

        # Third document_change edits the source file.
        source_edit = action.edit.document_changes[2]
        new_text    = source_edit.edits.first.new_text

        assert_match(/require_relative "greetable"/, new_text)
        refute_match(/module Greetable/, new_text)
      end

      def test_new_file_uri_is_in_same_directory_as_source
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end

          class User; end
        RUBY

        actions    = code_actions_for(source, line: 0)
        action     = find_action(actions, /Extract to include file/)
        refute_nil action

        create_op      = action.edit.document_changes.first
        source_dir     = File.dirname(URI("file:///test/fixture.rb").path)
        expected_path  = File.join(source_dir, "greetable.rb")

        assert_equal "file://#{expected_path}", create_op.uri
      end

      def test_converts_camel_case_module_name_to_snake_case_filename
        source = <<~RUBY
          module MyHelperModule
            def help = true
          end

          class App; end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /Extract to include file/)
        refute_nil action

        assert_match(/my_helper_module\.rb/, action.title)
        create_op = action.edit.document_changes.first
        assert_match(/my_helper_module\.rb/, create_op.uri)
      end

      def test_works_for_class_nodes_too
        source = <<~RUBY
          class AdminUser
            def admin? = true
          end

          class User; end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /Extract to include file/)
        refute_nil action

        assert_match(/admin_user\.rb/, action.title)
      end

      # ── negative cases ─────────────────────────────────────────────────────

      def test_does_not_offer_when_module_is_only_top_level_node
        # Nothing else in the file — extraction would leave an empty source.
        source = <<~RUBY
          module Greetable
            def greet = "hello"
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, /Extract to include file/)
      end

      def test_does_not_offer_for_nested_module
        source = <<~RUBY
          class User
            module Callbacks
              def before_save = nil
            end
          end
        RUBY

        # Cursor on the nested module (line 1)
        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /Extract to include file/)
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
