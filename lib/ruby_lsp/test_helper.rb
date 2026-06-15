# frozen_string_literal: true

require "ruby_lsp/internal"
require "ruby_lsp/ruby_lsp_refactor/addon"

module RubyLsp
  module Refactor
    # TestHelper provides lightweight integration scaffolding for testing
    # ruby-lsp-refactor listeners without spinning up a full LSP server.
    #
    # Usage in a Minitest test class:
    #
    #   class MyTest < Minitest::Test
    #     include RubyLsp::Refactor::TestHelper
    #
    #     def test_something
    #       actions = code_actions_for(source, line: 0)
    #       assert_includes actions.map(&:title), "Convert to post-conditional"
    #     end
    #   end
    module TestHelper
      # Parses +source+, runs the full listener pipeline via
      # Addon.refactor_actions_for, and returns the resulting code actions.
      # This exercises exactly the same path that runs inside the real LSP server.
      #
      # @param source [String]  Ruby source code to analyse.
      # @param line   [Integer] Zero-based line the cursor is on.
      # @param char   [Integer] Zero-based character offset (column).
      # @return [Array<Interface::CodeAction>]
      def code_actions_for(source, line: 0, char: 0)
        uri          = URI::Generic.from_path(path: "/test/fixture.rb")
        global_state = RubyLsp::GlobalState.new
        document     = RubyLsp::RubyDocument.new(
          source: source,
          version: 1,
          uri: uri,
          global_state: global_state
        )

        # LSP range hash — same shape the real server passes to CodeActions.
        range = {
          start: { line: line, character: char },
          end: { line: line, character: char }
        }

        RubyLsp::Refactor::Addon.refactor_actions_for(document, range)
      end
    end
  end
end
