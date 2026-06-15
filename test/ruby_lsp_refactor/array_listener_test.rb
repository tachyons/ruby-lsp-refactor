# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class ArrayListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      # ---------------------------------------------------------------------------
      # Core acceptance
      # ---------------------------------------------------------------------------

      def test_converts_symbol_array_to_percent_i
        source = "[:foo, :bar, :baz]\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to symbol array")
        refute_nil action

        edit = single_edit(action)
        assert_equal "%i[foo bar baz]", edit.new_text
      end

      def test_converts_single_element_symbol_array
        source = "[:only]\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to symbol array")
        refute_nil action

        edit = single_edit(action)
        assert_equal "%i[only]", edit.new_text
      end

      # ---------------------------------------------------------------------------
      # Negative cases
      # ---------------------------------------------------------------------------

      def test_does_not_offer_action_for_mixed_array
        source = "[:foo, 'bar']\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to symbol array")
      end

      def test_does_not_offer_action_for_empty_array
        source = "[]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to symbol array")
      end

      def test_does_not_offer_action_for_already_percent_i
        source = "%i[foo bar]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to symbol array")
      end

      def test_does_not_offer_action_for_integer_array
        source = "[1, 2, 3]\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to symbol array")
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
