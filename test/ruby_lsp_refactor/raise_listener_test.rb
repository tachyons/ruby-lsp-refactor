# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class RaiseListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_simplifies_raise_runtime_error
        source = "raise RuntimeError, \"something went wrong\"\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Simplify raise (remove redundant RuntimeError)")
        refute_nil action

        edit = single_edit(action)
        assert_equal 'raise "something went wrong"', edit.new_text.strip
      end

      def test_simplifies_fail_runtime_error
        source = "fail RuntimeError, \"oops\"\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Simplify raise (remove redundant RuntimeError)")
        refute_nil action

        edit = single_edit(action)
        assert_equal 'fail "oops"', edit.new_text.strip
      end

      def test_does_not_offer_for_other_exception_classes
        source = "raise ArgumentError, \"bad arg\"\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Simplify raise (remove redundant RuntimeError)")
      end

      def test_does_not_offer_for_raise_with_string_only
        source = "raise \"already simple\"\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Simplify raise (remove redundant RuntimeError)")
      end

      def test_does_not_offer_for_runtime_error_new
        source = "raise RuntimeError.new(\"msg\")\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Simplify raise (remove redundant RuntimeError)")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
