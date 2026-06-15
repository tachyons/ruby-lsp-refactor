# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class BlockStyleListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      # ── brace → do…end ────────────────────────────────────────────────────

      def test_converts_brace_block_to_do_end
        source = "users.each { |u| u.activate! }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to do…end block")
        refute_nil action

        edit = single_edit(action)
        assert_match(/do \|u\|/, edit.new_text)
        assert_match(/u\.activate!/, edit.new_text)
        assert_match(/end/, edit.new_text)
      end

      def test_brace_to_do_end_preserves_indentation
        source = "  users.each { |u| u.activate! }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to do…end block")
        refute_nil action

        edit = single_edit(action)
        # The edit replaces the node range which starts at column 2, so
        # new_text begins at the call itself (no leading spaces).
        assert_match(/\Ausers\.each do \|u\|/, edit.new_text)
        # Body is indented 2 (node column) + 2 (block body) = 4 spaces.
        assert_match(/^    u\.activate!/, edit.new_text)
        # Closing end is at the node's own indentation level (2 spaces).
        assert_match(/^  end$/, edit.new_text)
      end

      def test_brace_to_do_end_without_params
        source = "3.times { puts 'hi' }\n"
        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to do…end block")
        refute_nil action

        edit = single_edit(action)
        assert_match(/do\n/, edit.new_text)
        refute_match(/\|/, edit.new_text)
      end

      # ── do…end → brace ────────────────────────────────────────────────────

      def test_converts_do_end_block_to_brace
        source = <<~RUBY
          users.each do |u|
            u.activate!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to brace block")
        refute_nil action

        edit = single_edit(action)
        assert_match(/\{ \|u\| u\.activate! \}/, edit.new_text)
      end

      def test_does_not_offer_brace_for_multi_statement_do_end
        source = <<~RUBY
          users.each do |u|
            u.activate!
            u.notify!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to brace block")
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
