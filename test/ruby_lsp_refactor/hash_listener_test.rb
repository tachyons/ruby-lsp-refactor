# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class HashListenerTest < Minitest::Test
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

      def test_converts_hash_rocket_to_keyword_syntax
        source = "{ :foo => 1, :bar => 2 }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to keyword syntax")
        refute_nil action

        edit = single_edit(action)
        assert_equal "{ foo: 1, bar: 2 }", edit.new_text
      end

      def test_converts_mixed_hash_only_rocket_pairs
        # String key should be left verbatim; symbol rocket key should be converted.
        source = %({ "name" => "Alice", :age => 30 }\n)
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to keyword syntax")
        refute_nil action

        edit = single_edit(action)
        assert_match(/age: 30/, edit.new_text)
        assert_match(/"name" => "Alice"/, edit.new_text)
      end

      # ---------------------------------------------------------------------------
      # Negative cases
      # ---------------------------------------------------------------------------

      def test_does_not_offer_action_for_already_keyword_hash
        source = "{ foo: 1, bar: 2 }\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to keyword syntax")
      end

      def test_does_not_offer_action_for_empty_hash
        source = "{}\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to keyword syntax")
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
