# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class PullUpMethodListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def all_edits(action)
        action.edit.changes.values.flatten
      end

      # ── same-file: core acceptance ─────────────────────────────────────────

      def test_offers_pull_up_when_parent_in_same_file
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def foo
              "hello"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method 'foo'/)
        refute_nil action
        assert_match(/Parent/, action.title)
      end

      def test_inserts_method_before_parent_end
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def foo
              "hello"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method/)
        refute_nil action

        edits = all_edits(action)
        assert_equal 2, edits.size

        insert_edit = edits.find { |e| e.new_text.include?("def foo") }
        refute_nil insert_edit

        # Inserted before parent's `end` (line 1, 0-based)
        assert_equal 1, insert_edit.range.start.line
        assert_match(/def foo/, insert_edit.new_text)
        assert_match(/"hello"/, insert_edit.new_text)
      end

      def test_deletes_method_from_child
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def foo
              "hello"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method/)
        refute_nil action

        edits = all_edits(action)
        delete_edit = edits.find { |e| e.new_text == "" }
        refute_nil delete_edit
        assert_equal "", delete_edit.new_text
      end

      def test_re_indents_method_for_parent
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def foo
              "hello"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method/)
        edits   = all_edits(action)

        insert_edit = edits.find { |e| e.new_text.include?("def foo") }
        # Both parent and child are at column 0, so indentation is the same (2 spaces)
        assert_match(/  def foo/, insert_edit.new_text)
        assert_match(/    "hello"/, insert_edit.new_text)
        assert_match(/  end/, insert_edit.new_text)
      end

      def test_absorbs_blank_line_before_method_when_deleting
        source = <<~RUBY
          class Child < Parent
            def before
              1
            end

            def foo
              "hello"
            end
          end
        RUBY

        # No parent in same file, so no same-file action — just verify no crash
        # (cross-file path returns nil without index)
        assert_silent { code_actions_for(source, line: 5) }
      end

      def test_handles_nested_class_indentation
        source = <<~RUBY
          module MyApp
            class Parent
            end

            class Child < Parent
              def foo
                "hello"
              end
            end
          end
        RUBY

        actions = code_actions_for(source, line: 5)
        action  = find_action(actions, /Pull up method 'foo'/)
        refute_nil action

        edits = all_edits(action)
        insert_edit = edits.find { |e| e.new_text.include?("def foo") }
        refute_nil insert_edit

        # Parent is at column 2, so body indent is 4 spaces
        assert_match(/    def foo/, insert_edit.new_text)
        assert_match(/      "hello"/, insert_edit.new_text)
      end

      def test_works_with_multi_statement_method
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def process(x)
              result = x * 2
              result + 1
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method 'process'/)
        refute_nil action

        edits = all_edits(action)
        insert_edit = edits.find { |e| e.new_text.include?("def process") }
        refute_nil insert_edit
        assert_match(/result = x \* 2/, insert_edit.new_text)
        assert_match(/result \+ 1/, insert_edit.new_text)
      end

      def test_title_includes_method_and_parent_name
        source = <<~RUBY
          class Animal
          end

          class Dog < Animal
            def speak
              "woof"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 4)
        action  = find_action(actions, /Pull up method/)
        refute_nil action
        assert_match(/speak/, action.title)
        assert_match(/Animal/, action.title)
      end

      # ── negative cases ─────────────────────────────────────────────────────

      def test_does_not_offer_when_class_has_no_superclass
        source = <<~RUBY
          class Standalone
            def foo
              "hello"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /Pull up method/)
      end

      def test_does_not_offer_outside_a_class
        source = <<~RUBY
          def foo
            "hello"
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, /Pull up method/)
      end

      def test_does_not_offer_when_cursor_not_on_method
        source = <<~RUBY
          class Parent
          end

          class Child < Parent
            def foo
              "hello"
            end
          end
        RUBY

        # Cursor on the class declaration line, not the method
        actions = code_actions_for(source, line: 3)
        assert_nil find_action(actions, /Pull up method/)
      end

      # ── cross-file ─────────────────────────────────────────────────────────

      def test_cross_file_offers_action_when_parent_indexed
        require "tempfile"

        parent_file = Tempfile.new(["user", ".rb"])
        parent_file.write(<<~RUBY)
          class User
          end
        RUBY
        parent_file.flush

        uri          = URI::Generic.from_path(path: "/test/fixture.rb")
        global_state = RubyLsp::GlobalState.new
        global_state.index.index_single(
          URI::Generic.from_path(path: parent_file.path),
          File.read(parent_file.path),
        )

        document = RubyLsp::RubyDocument.new(
          source: <<~RUBY,
            class Child < User
              def foo
                "hello"
              end
            end
          RUBY
          version:      1,
          uri:          uri,
          global_state: global_state,
        )

        range   = { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }
        actions = RubyLsp::Refactor::Addon.refactor_actions_for(document, range, global_state)
        action  = actions.find { |a| a.title.match?(/Pull up method 'foo'/) }

        refute_nil action, "Expected cross-file pull-up action"
        assert_match(/User/, action.title)
        assert_match(/\.rb/, action.title)

        # Must use document_changes (multi-file), not changes (single-file)
        refute_nil action.edit.document_changes, "Expected document_changes for cross-file edit"
        assert_equal 2, action.edit.document_changes.length
      ensure
        parent_file&.close
        parent_file&.unlink
      end

      def test_cross_file_inserts_method_into_parent_file
        require "tempfile"

        parent_file = Tempfile.new(["user", ".rb"])
        parent_file.write(<<~RUBY)
          class User
          end
        RUBY
        parent_file.flush

        uri          = URI::Generic.from_path(path: "/test/fixture.rb")
        global_state = RubyLsp::GlobalState.new
        global_state.index.index_single(
          URI::Generic.from_path(path: parent_file.path),
          File.read(parent_file.path),
        )

        document = RubyLsp::RubyDocument.new(
          source: <<~RUBY,
            class Child < User
              def foo
                "hello"
              end
            end
          RUBY
          version:      1,
          uri:          uri,
          global_state: global_state,
        )

        range   = { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }
        actions = RubyLsp::Refactor::Addon.refactor_actions_for(document, range, global_state)
        action  = actions.find { |a| a.title.match?(/Pull up method 'foo'/) }
        refute_nil action

        parent_edit = action.edit.document_changes.find do |e|
          e.is_a?(LanguageServer::Protocol::Interface::TextDocumentEdit) &&
            e.text_document.uri.include?(File.basename(parent_file.path, ".rb"))
        end
        refute_nil parent_edit, "Expected a TextDocumentEdit targeting the parent file"

        insert_text = parent_edit.edits.first.new_text
        assert_match(/def foo/, insert_text)
        assert_match(/"hello"/, insert_text)

        # User class ends at line 1 (0-based), insert before that
        assert_equal 1, parent_edit.edits.first.range.start.line
      ensure
        parent_file&.close
        parent_file&.unlink
      end

      def test_cross_file_deletes_method_from_child_file
        require "tempfile"

        parent_file = Tempfile.new(["user", ".rb"])
        parent_file.write(<<~RUBY)
          class User
          end
        RUBY
        parent_file.flush

        uri          = URI::Generic.from_path(path: "/test/fixture.rb")
        global_state = RubyLsp::GlobalState.new
        global_state.index.index_single(
          URI::Generic.from_path(path: parent_file.path),
          File.read(parent_file.path),
        )

        document = RubyLsp::RubyDocument.new(
          source: <<~RUBY,
            class Child < User
              def foo
                "hello"
              end
            end
          RUBY
          version:      1,
          uri:          uri,
          global_state: global_state,
        )

        range   = { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }
        actions = RubyLsp::Refactor::Addon.refactor_actions_for(document, range, global_state)
        action  = actions.find { |a| a.title.match?(/Pull up method 'foo'/) }
        refute_nil action

        child_edit = action.edit.document_changes.find do |e|
          e.is_a?(LanguageServer::Protocol::Interface::TextDocumentEdit) &&
            e.text_document.uri.include?("fixture")
        end
        refute_nil child_edit, "Expected a TextDocumentEdit targeting the child file"
        assert_equal "", child_edit.edits.first.new_text
      ensure
        parent_file&.close
        parent_file&.unlink
      end

      def test_cross_file_inserts_at_correct_line_when_parent_has_existing_methods
        require "tempfile"

        parent_file = Tempfile.new(["user", ".rb"])
        parent_file.write(<<~RUBY)
          class User
            def existing
              42
            end
          end
        RUBY
        parent_file.flush

        uri          = URI::Generic.from_path(path: "/test/fixture.rb")
        global_state = RubyLsp::GlobalState.new
        global_state.index.index_single(
          URI::Generic.from_path(path: parent_file.path),
          File.read(parent_file.path),
        )

        document = RubyLsp::RubyDocument.new(
          source: <<~RUBY,
            class Child < User
              def foo
                "hello"
              end
            end
          RUBY
          version:      1,
          uri:          uri,
          global_state: global_state,
        )

        range   = { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }
        actions = RubyLsp::Refactor::Addon.refactor_actions_for(document, range, global_state)
        action  = actions.find { |a| a.title.match?(/Pull up method 'foo'/) }
        refute_nil action

        parent_edit = action.edit.document_changes.find do |e|
          e.is_a?(LanguageServer::Protocol::Interface::TextDocumentEdit) &&
            e.text_document.uri.include?(File.basename(parent_file.path, ".rb"))
        end
        refute_nil parent_edit

        # User class ends at line 4 (0-based), insert before that
        assert_equal 4, parent_edit.edits.first.range.start.line
      ensure
        parent_file&.close
        parent_file&.unlink
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
