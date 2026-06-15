# frozen_string_literal: true

require "minitest/autorun"
require "ruby_lsp/test_helper"

module RubyLsp
  module Refactor
    class MethodListenerTest < Minitest::Test
      include RubyLsp::Refactor::TestHelper

      def find_action(actions, title_pattern)
        actions.find { |a| a.title.match?(title_pattern) }
      end

      def all_edits(action)
        action.edit.changes.values.flatten
      end

      # ===========================================================================
      # 1. Extract to method
      # ===========================================================================

      def test_extract_to_method_replaces_rhs_and_inserts_new_method
        source = <<~RUBY
          def process
            result = expensive_computation
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        action  = find_action(actions, /Extract to method/)
        refute_nil action

        edits = all_edits(action)
        assert_equal 2, edits.size

        replace_edit = edits.find { |e| e.new_text.include?("result") && !e.new_text.include?("def") }
        insert_edit  = edits.find { |e| e.new_text.include?("def result") }

        refute_nil replace_edit, "Expected an edit replacing the RHS with a method call"
        refute_nil insert_edit,  "Expected an edit inserting the new method definition"

        assert_match(/def result/, insert_edit.new_text)
        assert_match(/expensive_computation/, insert_edit.new_text)
      end

      def test_extract_to_method_passes_outer_variables_as_params
        source = <<~RUBY
          def process(data)
            threshold = 10
            result = data.select { |x| x > threshold }
          end
        RUBY

        # Cursor on the `result =` line (line 2).
        actions = code_actions_for(source, line: 2)
        action  = find_action(actions, /Extract to method/)
        refute_nil action

        edits = all_edits(action)
        insert_edit = edits.find { |e| e.new_text.include?("def result") }
        refute_nil insert_edit

        # `threshold` was defined before the extraction point and is used in the RHS.
        assert_match(/def result\(threshold\)/, insert_edit.new_text)
      end

      # ===========================================================================
      # 2. Add parameter
      # ===========================================================================

      def test_add_parameter_appends_to_existing_params
        source = <<~RUBY
          def greet(name)
            puts name
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Add parameter")
        refute_nil action

        edits = all_edits(action)
        assert_equal 1, edits.size

        edit = edits.first
        assert_equal ", new_param", edit.new_text
      end

      def test_add_parameter_creates_parens_when_no_params
        source = <<~RUBY
          def greet
            puts "hello"
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Add parameter")
        refute_nil action

        edits = all_edits(action)
        assert_equal 1, edits.size

        edit = edits.first
        assert_equal "(new_param)", edit.new_text
      end

      # ===========================================================================
      # 3. Convert to keyword arguments
      # ===========================================================================

      def test_converts_positional_params_to_kwargs
        source = <<~RUBY
          def create(name, age)
            User.new(name, age)
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        action  = find_action(actions, "Convert to keyword arguments")
        refute_nil action

        edits = all_edits(action)
        assert_equal 1, edits.size

        edit = edits.first
        assert_equal "name:, age:", edit.new_text
      end

      def test_does_not_offer_kwargs_conversion_when_no_positional_params
        source = <<~RUBY
          def greet
            puts "hello"
          end
        RUBY

        actions = code_actions_for(source, line: 0)
        assert_nil find_action(actions, "Convert to keyword arguments")
      end

      # ===========================================================================
      # 4. Extract to let (RSpec)
      # ===========================================================================

      def test_extract_to_let_inserts_let_block_and_removes_assignment
        source = <<~RUBY
          describe "User" do
            it "logs in" do
              user = User.new(name: "Alice")
              expect(user.name).to eq("Alice")
            end
          end
        RUBY

        # Cursor on the `user =` line (line 2).
        actions = code_actions_for(source, line: 2)
        action  = find_action(actions, /Extract to let/)
        refute_nil action

        edits = all_edits(action)
        assert_equal 2, edits.size

        insert_edit = edits.find { |e| e.new_text.include?("let(") }
        delete_edit = edits.find { |e| e.new_text == "" }

        refute_nil insert_edit, "Expected an edit inserting a let block"
        refute_nil delete_edit, "Expected an edit deleting the original assignment"

        assert_match(/let\(:user\)/, insert_edit.new_text)
        assert_match(/User\.new\(name: "Alice"\)/, insert_edit.new_text)
      end

      def test_does_not_offer_extract_to_let_outside_rspec_example
        source = <<~RUBY
          def setup
            user = User.new
          end
        RUBY

        actions = code_actions_for(source, line: 1)
        assert_nil find_action(actions, /Extract to let/)
      end

      # ---------------------------------------------------------------------------
      # Resilience
      # ---------------------------------------------------------------------------

      def test_does_not_raise_on_empty_source
        assert_silent { code_actions_for("", line: 0) }
      end
    end
  end
end
