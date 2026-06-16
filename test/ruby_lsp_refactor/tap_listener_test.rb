# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class TapListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      # ── core acceptance ────────────────────────────────────────────────────

      def test_converts_sequence_to_tap
        source = <<~RUBY
          def do_something
            obj.do_first_thing
            obj.do_second_thing
            obj.do_third_thing
            obj
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to tap")
        refute_nil action

        edit = single_edit(action)
        assert_match(/obj\.tap do \|o\|/, edit.new_text)
        assert_match(/o\.do_first_thing/, edit.new_text)
        assert_match(/o\.do_second_thing/, edit.new_text)
        assert_match(/o\.do_third_thing/, edit.new_text)
        assert_match(/end/, edit.new_text)
        refute_match(/\bobj\b(?!\.tap)/, edit.new_text.sub("obj.tap", ""))
      end

      def test_preserves_method_arguments
        source = <<~RUBY
          def setup
            user.assign_role(:admin)
            user.set_name("Alice")
            user
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to tap")
        refute_nil action

        edit = single_edit(action)
        assert_match(/user\.tap do \|o\|/, edit.new_text)
        assert_match(/o\.assign_role\(:admin\)/, edit.new_text)
        assert_match(/o\.set_name\("Alice"\)/, edit.new_text)
      end

      def test_preserves_indentation
        source = <<~RUBY
          class Builder
            def build
              obj.step_one
              obj.step_two
              obj
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Convert to tap")
        refute_nil action

        edit = single_edit(action)
        # The body range starts at the method body's indentation (4 spaces).
        assert_match(/\A    obj\.tap do \|o\|/, edit.new_text)
        assert_match(/      o\.step_one/, edit.new_text)
      end

      # ── negative cases ─────────────────────────────────────────────────────

      def test_does_not_offer_when_last_statement_is_not_bare_receiver
        source = <<~RUBY
          def do_something
            obj.step_one
            obj.step_two
            obj.result
          end
        RUBY

        # last statement is a call on obj, not a bare variable read
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to tap")
      end

      def test_does_not_offer_when_receivers_differ
        source = <<~RUBY
          def do_something
            foo.step_one
            bar.step_two
            foo
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to tap")
      end

      def test_does_not_offer_for_single_statement_method
        source = <<~RUBY
          def do_something
            obj
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to tap")
      end

      def test_does_not_offer_outside_a_method
        source = <<~RUBY
          obj.step_one
          obj.step_two
          obj
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to tap")
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
