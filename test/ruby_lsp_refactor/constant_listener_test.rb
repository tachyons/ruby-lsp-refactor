# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class ConstantListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title)
        actions.find { |a| a.title == title }
      end

      def test_extracts_integer_literal_to_constant
        source = <<~RUBY
          class Processor
            def run
              items.first(100)
            end
          end
        RUBY

        actions = code_actions_for(source, line: 2)
        action  = find_action(actions, "Extract constant")
        refute_nil action

        edits = action.edit.changes.values.flatten
        assert_equal 2, edits.size

        insert_edit  = edits.find { |e| e.new_text.include?("EXTRACTED_CONSTANT") && e.new_text.include?("=") }
        replace_edit = edits.find { |e| e.new_text == "EXTRACTED_CONSTANT" }

        refute_nil insert_edit
        refute_nil replace_edit
        assert_match(/EXTRACTED_CONSTANT = 100/, insert_edit.new_text)
      end

      def test_extracts_string_literal_to_constant
        source = <<~RUBY
          class Mailer
            def subject
              "Welcome to the app"
            end
          end
        RUBY

        actions = code_actions_for(source, line: 2)
        action  = find_action(actions, "Extract constant")
        refute_nil action

        edits = action.edit.changes.values.flatten
        insert_edit = edits.find { |e| e.new_text.include?("EXTRACTED_CONSTANT") && e.new_text.include?("=") }
        assert_match(/EXTRACTED_CONSTANT = "Welcome to the app"/, insert_edit.new_text)
      end

      def test_does_not_offer_outside_class
        source = "items.first(100)\n"
        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Extract constant")
      end

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
