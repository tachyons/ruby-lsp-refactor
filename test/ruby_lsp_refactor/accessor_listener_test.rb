# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class AccessorListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def test_collapses_attr_reader_and_writer_into_attr_accessor
        source = <<~RUBY
          class User
            attr_reader :name

            def name=(val)
              @name = val
            end
          end
        RUBY

        # Cursor on the attr_reader line
        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, /attr_accessor :name/)
        refute_nil action

        edits = action.edit.changes.values.flatten
        assert_equal 2, edits.size

        replace_edit = edits.find { |e| e.new_text.include?("attr_accessor") }
        delete_edit  = edits.find { |e| e.new_text == "" }

        refute_nil replace_edit
        refute_nil delete_edit
        assert_match(/attr_accessor :name/, replace_edit.new_text)
      end

      def test_offers_action_from_writer_def_line_too
        source = <<~RUBY
          class User
            attr_reader :name

            def name=(val)
              @name = val
            end
          end
        RUBY

        # Cursor on the def name= line
        actions = code_actions_for(source, line: 3)
        action  = find_action(actions, /attr_accessor :name/)
        refute_nil action
      end

      def test_does_not_offer_when_no_matching_writer
        source = <<~RUBY
          class User
            attr_reader :name
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /attr_accessor/)
      end

      def test_does_not_offer_for_non_canonical_writer
        # Writer has extra logic — not a simple passthrough
        source = <<~RUBY
          class User
            attr_reader :name

            def name=(val)
              @name = val.strip
            end
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /attr_accessor/)
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
