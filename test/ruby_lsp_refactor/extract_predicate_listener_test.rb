# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class ExtractPredicateListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def all_edits(action)
        action.edit.changes.values.flatten
      end

      # ── core acceptance ────────────────────────────────────────────────────

      def test_extracts_and_compound_into_predicate_methods
        source = <<~RUBY
          def eligible_for_return?
            expired_orders.exclude?(self) && self.value > MINIMUM_RETURN_VALUE
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Extract predicate methods")
        refute_nil action

        edits = all_edits(action)
        assert_equal 2, edits.size

        replace_edit = edits.find { |e| e.new_text.include?("predicate_1?") && e.new_text.include?("&&") }
        insert_edit  = edits.find { |e| e.new_text.include?("def predicate_1?") }

        refute_nil replace_edit
        refute_nil insert_edit

        assert_match(/predicate_1\? && predicate_2\?/, replace_edit.new_text)
        assert_match(/def predicate_1\?/, insert_edit.new_text)
        assert_match(/expired_orders\.exclude\?\(self\)/, insert_edit.new_text)
        assert_match(/def predicate_2\?/, insert_edit.new_text)
        assert_match(/self\.value > MINIMUM_RETURN_VALUE/, insert_edit.new_text)
      end

      def test_extracts_or_compound_into_predicate_methods
        source = <<~RUBY
          def should_notify?
            user.admin? || user.subscribed?
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Extract predicate methods")
        refute_nil action

        edits = all_edits(action)
        replace_edit = edits.find { |e| e.new_text.include?("||") }
        insert_edit  = edits.find { |e| e.new_text.include?("def predicate_1?") }

        refute_nil replace_edit
        refute_nil insert_edit
        assert_match(/predicate_1\? \|\| predicate_2\?/, replace_edit.new_text)
        assert_match(/user\.admin\?/, insert_edit.new_text)
        assert_match(/user\.subscribed\?/, insert_edit.new_text)
      end

      def test_inserts_private_section_after_def
        source = <<~RUBY
          def eligible?
            a? && b?
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Extract predicate methods")
        refute_nil action

        edits = all_edits(action)
        insert_edit = edits.find { |e| e.new_text.include?("def predicate_1?") }
        assert_match(/private/, insert_edit.new_text)
      end

      # ── negative cases ─────────────────────────────────────────────────────

      def test_does_not_offer_when_method_has_multiple_statements
        source = <<~RUBY
          def process
            validate!
            a? && b?
          end
        RUBY

        actions = code_actions_for(source, line: 2)
        assert_nil find_action(actions, "Extract predicate methods")
      end

      def test_does_not_offer_outside_a_method
        source = "a? && b?\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Extract predicate methods")
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
