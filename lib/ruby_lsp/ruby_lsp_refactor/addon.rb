# frozen_string_literal: true

require "ruby_lsp/addon"
require "ruby_lsp/requests/code_actions"
require "ruby_lsp/requests/code_action_resolve"
require_relative "listeners/conditional_listener"
require_relative "listeners/variable_listener"
require_relative "listeners/string_listener"
require_relative "listeners/hash_listener"
require_relative "listeners/array_listener"
require_relative "listeners/method_listener"

module RubyLsp
  module Refactor
    # Lightweight value object that satisfies the interface expected by every
    # listener: #uri and #range.
    NodeContext = Struct.new(:uri, :range)

    # Prepended into RubyLsp::Requests::CodeActions#perform.
    #
    # Runs our own AST walk and appends the resulting actions to whatever
    # ruby-lsp itself returns.  Each action carries a full `edit:` so no
    # resolve round-trip is needed (the LSP spec allows this).
    module CodeActionsExtension
      def perform
        actions = super || []
        actions.concat(RubyLsp::Refactor::Addon.refactor_actions_for(@document, @range))
        actions
      end
    end

    class Addon < ::RubyLsp::Addon
      # Called once when the language server activates this add-on.
      def activate(global_state, message_queue)
        @global_state = global_state

        # Inject our actions into the standard code-actions response.
        RubyLsp::Requests::CodeActions.prepend(CodeActionsExtension)
      end

      def deactivate; end

      def name
        "Ruby LSP Refactor"
      end

      def version
        "0.1.0"
      end

      # Runs the full listener pipeline against +document+ at +range+ and
      # returns an array of Interface::CodeAction objects.
      #
      # Called from CodeActionsExtension#perform and from the test helper.
      #
      # @param document [RubyLsp::RubyDocument]
      # @param range    [Hash]  LSP range hash { start: {line:, character:}, end: {line:, character:} }
      # @return [Array<Interface::CodeAction>]
      def self.refactor_actions_for(document, range)
        return [] unless document.is_a?(RubyLsp::RubyDocument)
        return [] if document.source.empty?

        cursor_range = Interface::Range.new(
          start: Interface::Position.new(
            line:      range.dig(:start, :line),
            character: range.dig(:start, :character),
          ),
          end: Interface::Position.new(
            line:      range.dig(:end, :line),
            character: range.dig(:end, :character),
          ),
        )

        node_context     = NodeContext.new(document.uri.to_s, cursor_range)
        response_builder = RubyLsp::ResponseBuilders::CollectionResponseBuilder.new
        dispatcher       = Prism::Dispatcher.new

        # Phase 1 – Local rewrites
        ConditionalListener.new(response_builder, node_context, dispatcher)
        StringListener.new(response_builder, node_context, dispatcher)

        # Phase 2 – Variable & literal optimisation
        VariableListener.new(response_builder, node_context, dispatcher)
        HashListener.new(response_builder, node_context, dispatcher)
        ArrayListener.new(response_builder, node_context, dispatcher)

        # Phase 3 – Advanced structure
        MethodListener.new(response_builder, node_context, dispatcher)

        dispatcher.dispatch(document.ast)
        response_builder.response
      rescue StandardError
        []
      end
    end
  end
end
