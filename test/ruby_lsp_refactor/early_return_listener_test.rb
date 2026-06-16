# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class EarlyReturnListenerTest < Minitest::Test
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

      def test_converts_guard_if_to_early_return
        source = <<~RUBY
          def charge_purchase(order)
            if order.fulfilled?
              OrderChargeConfirmation.new(order).create!
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Convert to early return")
        refute_nil action

        edit = single_edit(action)
        assert_match(/return unless order\.fulfilled\?/, edit.new_text)
        assert_match(/OrderChargeConfirmation\.new\(order\)\.create!/, edit.new_text)
        refute_match(/\bif\b/, edit.new_text)
        refute_match(/\bend\b/, edit.new_text)
      end

      def test_preserves_multi_statement_body
        source = <<~RUBY
          def process(order)
            if order.valid?
              order.charge!
              order.notify!
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, "Convert to early return")
        refute_nil action

        edit = single_edit(action)
        assert_match(/return unless order\.valid\?/, edit.new_text)
        assert_match(/order\.charge!/, edit.new_text)
        assert_match(/order\.notify!/, edit.new_text)
      end

      def test_preserves_indentation
        source = <<~RUBY
          class Service
            def call(user)
              if user.active?
                user.run!
              end
            end
          end
        RUBY

        actions = code_actions_for(source, line: 2)
        action  = find_action(actions, "Convert to early return")
        refute_nil action

        edit = single_edit(action)
        # The edit replaces the if node range (start_column=4), so new_text
        # begins with the node's own indentation (4 spaces).
        assert_match(/\A    return unless user\.active\?/, edit.new_text)
        assert_match(/user\.run!/, edit.new_text)
      end

      # ── negative cases ─────────────────────────────────────────────────────

      def test_does_not_offer_when_if_has_else
        source = <<~RUBY
          def process(order)
            if order.valid?
              order.charge!
            else
              order.reject!
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, "Convert to early return")
      end

      def test_does_not_offer_when_if_has_elsif
        source = <<~RUBY
          def process(order)
            if order.paid?
              order.complete!
            elsif order.pending?
              order.charge!
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, "Convert to early return")
      end

      def test_does_not_offer_when_if_is_not_first_statement
        source = <<~RUBY
          def process(order)
            order.validate!
            if order.valid?
              order.charge!
            end
          end
        RUBY

        # Cursor on the if (line 2) — it is not the first statement
        actions = code_actions_for(source, line: 2)
        assert_nil find_action(actions, "Convert to early return")
      end

      def test_does_not_offer_outside_a_method
        source = <<~RUBY
          if user.active?
            user.run!
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to early return")
      end

      def test_does_not_offer_for_post_conditional
        source = "user.run! if user.active?\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to early return")
      end

      # ── resilience ─────────────────────────────────────────────────────────

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
