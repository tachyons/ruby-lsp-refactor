# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class EnumerableListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      # ── map + flatten → flat_map ───────────────────────────────────────────

      def test_converts_map_flatten_1_to_flat_map
        source = "items.map { |i| i.tags }.flatten(1)\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to .flat_map")
        refute_nil action

        edit = single_edit(action)
        assert_equal "items.flat_map { |i| i.tags }", edit.new_text.strip
      end

      def test_converts_map_flatten_no_arg_to_flat_map
        source = "items.map { |i| i.tags }.flatten\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to .flat_map")
        refute_nil action

        edit = single_edit(action)
        assert_equal "items.flat_map { |i| i.tags }", edit.new_text.strip
      end

      def test_does_not_offer_flat_map_for_flatten_2
        source = "items.map { |i| i.tags }.flatten(2)\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to .flat_map")
      end

      # ── select + first → find ─────────────────────────────────────────────

      def test_converts_select_first_to_find
        source = "users.select { |u| u.admin? }.first\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to .find")
        refute_nil action

        edit = single_edit(action)
        assert_equal "users.find { |u| u.admin? }", edit.new_text.strip
      end

      # ── map + compact → filter_map ────────────────────────────────────────

      def test_converts_map_compact_to_filter_map
        source = "items.map { |i| i.value }.compact\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to .filter_map")
        refute_nil action

        edit = single_edit(action)
        assert_equal "items.filter_map { |i| i.value }", edit.new_text.strip
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
