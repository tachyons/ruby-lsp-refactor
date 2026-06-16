# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class VariableListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def all_edits(action)
        action.edit.changes.values.flatten
      end

      # ===========================================================================
      # 1. Inline variable
      # ===========================================================================

      def test_inline_variable_replaces_reads_and_deletes_assignment
        source = <<~RUBY
          result = user.calculate
          puts result
          log result
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /Inline variable/)
        refute_nil action

        edits = all_edits(action)
        # 1 delete + 2 replacements
        assert_equal 3, edits.size

        delete_edit = edits.find { |e| e.new_text == "" }
        refute_nil delete_edit
        assert_equal 0, delete_edit.range.start.line

        replace_edits = edits.reject { |e| e.new_text == "" }
        replace_edits.each { |e| assert_equal "user.calculate", e.new_text }
      end

      def test_inline_variable_title_includes_variable_name
        source = "total = price * qty\nputs total\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /Inline variable/)
        refute_nil action
        assert_match(/total/, action.title)
      end

      def test_does_not_offer_inline_when_cursor_not_on_assignment
        source = <<~RUBY
          result = user.calculate
          puts result
        RUBY

        # Cursor on the `puts` line, not the assignment.
        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /Inline variable/)
      end

      # ---------------------------------------------------------------------------
      # Resilience
      # ---------------------------------------------------------------------------

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
