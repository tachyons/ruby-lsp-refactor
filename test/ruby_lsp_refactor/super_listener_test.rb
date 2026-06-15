# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class SuperListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def single_edit(action)
        edits = action.edit.changes.values.flatten
        assert_equal 1, edits.size
        edits.first
      end

      def test_converts_bare_super_to_explicit
        source = <<~RUBY
          def initialize(name, age)
            super
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, /explicit super/)
        refute_nil action

        edit = single_edit(action)
        assert_equal "super(name, age)", edit.new_text.strip
      end

      def test_title_includes_param_names
        source = <<~RUBY
          def initialize(name, age)
            super
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, /explicit super/)
        refute_nil action
        assert_match(/name, age/, action.title)
      end

      def test_does_not_offer_when_no_params
        source = <<~RUBY
          def initialize
            super
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /explicit super/)
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
