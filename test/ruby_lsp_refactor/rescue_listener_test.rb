# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class RescueListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_wraps_method_body_in_rescue
        source = <<~RUBY
          def call
            do_thing
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Wrap body in rescue")
        refute_nil action

        edit = single_edit(action)
        assert_match(/rescue StandardError => e/, edit.new_text)
        assert_match(/do_thing/, edit.new_text)
        assert_match(/raise/, edit.new_text)
      end

      def test_preserves_all_body_statements
        source = <<~RUBY
          def process
            step_one
            step_two
            step_three
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Wrap body in rescue")
        refute_nil action

        edit = single_edit(action)
        assert_match(/step_one/, edit.new_text)
        assert_match(/step_two/, edit.new_text)
        assert_match(/step_three/, edit.new_text)
      end

      def test_does_not_offer_on_empty_method
        source = <<~RUBY
          def noop
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Wrap body in rescue")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
