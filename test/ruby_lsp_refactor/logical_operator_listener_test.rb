# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class LogicalOperatorListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_converts_double_ampersand_to_and
        source = "user.valid? && user.save\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /&&.*and/)
        refute_nil action

        edit = single_edit(action)
        assert_equal "user.valid? and user.save", edit.new_text.strip
      end

      def test_converts_and_to_double_ampersand
        source = "user.valid? and user.save\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /and.*&&/)
        refute_nil action

        edit = single_edit(action)
        assert_equal "user.valid? && user.save", edit.new_text.strip
      end

      def test_converts_double_pipe_to_or
        source = "a || b\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /\|\|.*or/)
        refute_nil action

        edit = single_edit(action)
        assert_equal "a or b", edit.new_text.strip
      end

      def test_converts_or_to_double_pipe
        source = "a or b\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, /or.*\|\|/)
        refute_nil action

        edit = single_edit(action)
        assert_equal "a || b", edit.new_text.strip
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
