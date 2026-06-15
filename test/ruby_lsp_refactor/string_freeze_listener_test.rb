# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class StringFreezeListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_wraps_string_in_freeze
        source = "\"hello world\"\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Wrap in freeze")
        refute_nil action

        edit = single_edit(action)
        assert_equal '"hello world".freeze', edit.new_text
      end

      def test_removes_freeze_from_frozen_string
        source = "\"hello world\".freeze\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Remove freeze")
        refute_nil action

        edit = single_edit(action)
        assert_equal '"hello world"', edit.new_text
      end

      def test_does_not_offer_wrap_when_already_frozen
        source = "\"hello\".freeze\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Wrap in freeze")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
