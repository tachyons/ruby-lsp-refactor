# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class StringArrayListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_converts_bracket_string_array_to_percent_w
        source = "[\"foo\", \"bar\", \"baz\"]\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to string array (%w[])")
        refute_nil action

        edit = single_edit(action)
        assert_equal "%w[foo bar baz]", edit.new_text
      end

      def test_converts_percent_w_to_bracket_array
        source = "%w[foo bar baz]\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to bracket array")
        refute_nil action

        edit = single_edit(action)
        assert_equal '["foo", "bar", "baz"]', edit.new_text
      end

      def test_does_not_offer_percent_w_for_strings_with_spaces
        source = "[\"hello world\", \"foo\"]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to string array (%w[])")
      end

      def test_does_not_offer_percent_w_for_mixed_array
        source = "[\"foo\", 42]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to string array (%w[])")
      end

      def test_does_not_offer_percent_w_for_empty_array
        source = "[]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to string array (%w[])")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
