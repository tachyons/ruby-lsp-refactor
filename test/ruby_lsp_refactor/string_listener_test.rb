# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class StringListenerTest < Minitest::Test
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

      def test_converts_single_quoted_string_to_double_quoted
        source = "'hello world'\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to interpolated string")
        refute_nil action

        edit = single_edit(action)
        assert_equal '"hello world"', edit.new_text
      end

      def test_escapes_embedded_double_quotes
        source = %('say "hi"' \n)
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to interpolated string")
        refute_nil action

        edit = single_edit(action)
        assert_equal '"say \"hi\""', edit.new_text
      end

      # ---------------------------------------------------------------------------
      # Negative cases
      # ---------------------------------------------------------------------------

      def test_does_not_offer_action_for_already_double_quoted_string
        source = '"hello world"' + "\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to interpolated string")
      end

      def test_does_not_offer_action_for_interpolated_string
        source = '"hello #{name}"' + "\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to interpolated string")
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
