# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class RspecLetListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_converts_let_to_let_bang
        source = "let(:user) { User.new }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert let to let!")
        refute_nil action

        edit = single_edit(action)
        assert_match(/let!\(:user\)/, edit.new_text)
      end

      def test_converts_let_bang_to_let
        source = "let!(:user) { User.new }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert let! to let")
        refute_nil action

        edit = single_edit(action)
        assert_match(/\blet\(:user\)/, edit.new_text)
        refute_match(/let!/, edit.new_text)
      end

      def test_does_not_offer_for_non_let_calls
        source = "subject { User.new }\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert let to let!")
        assert_nil find_action(actions, "Convert let! to let")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
