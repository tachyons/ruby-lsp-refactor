# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class ConditionalListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      # ---------------------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------------------

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size, "Expected exactly one TextEdit, got #{edits.size}"
        edits.first
      end

      # ===========================================================================
      # 1. Convert to post-conditional (block if → post-if)
      # ===========================================================================

      def test_converts_simple_if_block_to_post_conditional
        source = <<~RUBY
          if user.qualified?
            user.approve!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to post-conditional")
        refute_nil action, "Expected a 'Convert to post-conditional' code action"

        edit = single_edit(action)
        assert_equal "user.approve! if user.qualified?", edit.new_text.strip
      end

      def test_does_not_offer_post_conditional_for_if_with_else
        source = <<~RUBY
          if user.qualified?
            user.approve!
          else
            user.reject!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to post-conditional")
      end

      def test_does_not_offer_post_conditional_for_if_with_elsif
        source = <<~RUBY
          if user.admin?
            user.grant_admin!
          elsif user.qualified?
            user.approve!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to post-conditional")
      end

      def test_does_not_offer_post_conditional_for_multi_statement_body
        source = <<~RUBY
          if user.qualified?
            user.approve!
            notify(user)
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to post-conditional")
      end

      def test_post_conditional_preserves_leading_indentation
        source = <<~RUBY
          def process
            if user.qualified?
              user.approve!
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Convert to post-conditional")
        refute_nil action

        edit = single_edit(action)
        assert_match(/\A  user\.approve! if user\.qualified\?/, edit.new_text)
      end

      def test_post_conditional_edit_range_covers_entire_if_block
        source = <<~RUBY
          if user.qualified?
            user.approve!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        edit    = single_edit(find_action(actions, "Convert to post-conditional"))

        assert_equal 0, edit.range.start.line
        assert_equal 2, edit.range.end.line
      end

      def test_converts_unless_block_to_post_conditional
        source = <<~RUBY
          unless user.banned?
            user.login!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to post-conditional")
        refute_nil action

        edit = single_edit(action)
        assert_equal "user.login! unless user.banned?", edit.new_text.strip
      end

      # ===========================================================================
      # 2. Convert to block if (post-if → block if)
      # ===========================================================================

      def test_converts_post_conditional_to_block_if
        source = "user.approve! if user.qualified?\n"

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to block if")
        refute_nil action, "Expected a 'Convert to block if' code action"

        edit = single_edit(action)
        assert_match(/if user\.qualified\?/, edit.new_text)
        assert_match(/user\.approve!/, edit.new_text)
        assert_match(/end/, edit.new_text)
      end

      def test_converts_post_conditional_unless_to_block_unless
        source = "user.login! unless user.banned?\n"

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to block unless")
        refute_nil action

        edit = single_edit(action)
        assert_match(/unless user\.banned\?/, edit.new_text)
        assert_match(/user\.login!/, edit.new_text)
        assert_match(/end/, edit.new_text)
      end

      # ===========================================================================
      # 3. Toggle if ↔ unless
      # ===========================================================================

      def test_toggles_if_to_unless
        source = <<~RUBY
          if user.active?
            user.greet!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to unless")
        refute_nil action

        edit = single_edit(action)
        assert_match(/unless user\.active\?/, edit.new_text)
        assert_match(/user\.greet!/, edit.new_text)
      end

      def test_toggles_unless_to_if
        source = <<~RUBY
          unless user.banned?
            user.login!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to if")
        refute_nil action

        edit = single_edit(action)
        assert_match(/if user\.banned\?/, edit.new_text)
        assert_match(/user\.login!/, edit.new_text)
      end

      def test_toggle_if_with_bang_predicate_strips_negation
        source = <<~RUBY
          if !user.banned?
            user.login!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to unless")
        refute_nil action

        edit = single_edit(action)
        # The `!` should be stripped: `unless user.banned?`
        assert_match(/unless user\.banned\?/, edit.new_text)
        refute_match(/!user/, edit.new_text)
      end

      def test_does_not_offer_toggle_when_else_present
        source = <<~RUBY
          if user.active?
            greet!
          else
            reject!
          end
        RUBY

        # Toggle should not appear; invert should appear instead.
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to unless")
      end

      # ===========================================================================
      # 4. Invert if/else
      # ===========================================================================

      def test_inverts_if_else_branches
        source = <<~RUBY
          if user.admin?
            grant!
          else
            deny!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Invert if/else")
        refute_nil action

        edit = single_edit(action)
        # Predicate should be negated and branches swapped.
        assert_match(/if !user\.admin\?/, edit.new_text)
        # deny! should now be in the then-branch (first after if)
        deny_pos  = edit.new_text.index("deny!")
        grant_pos = edit.new_text.index("grant!")
        assert deny_pos < grant_pos, "deny! should appear before grant! after inversion"
      end

      def test_invert_cancels_double_negation
        source = <<~RUBY
          if !user.banned?
            allow!
          else
            block!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Invert if/else")
        refute_nil action

        edit = single_edit(action)
        # `!(!user.banned?)` should simplify to `user.banned?`
        assert_match(/if user\.banned\?/, edit.new_text)
        refute_match(/!!/, edit.new_text)
      end

      def test_does_not_offer_invert_without_else
        source = <<~RUBY
          if user.active?
            greet!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Invert if/else")
      end

      # ===========================================================================
      # Resilience
      # ===========================================================================

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end

      def test_does_not_raise_on_incomplete_if
        source = "if user.qualified?\n"
        assert_silent { code_actions_for(source, line: 0) }
      end

      def test_does_not_offer_action_when_cursor_is_outside_node
        source = <<~RUBY
          if user.qualified?
            user.approve!
          end
          puts "done"
        RUBY

        actions = code_actions_for(source, line: 3)
        assert_nil find_action(actions, "Convert to post-conditional")
      end
    end
  end
end
