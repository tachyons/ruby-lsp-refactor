# frozen_string_literal: true

require "ruby_lsp/addon"

# Conditionals
require_relative "listeners/conditional_listener"
require_relative "listeners/early_return_listener"

# Strings
require_relative "listeners/string_listener"
require_relative "listeners/string_array_listener"
require_relative "listeners/string_freeze_listener"

# Collections
require_relative "listeners/array_listener"
require_relative "listeners/hash_listener"
require_relative "listeners/enumerable_listener"

# Variables & constants
require_relative "listeners/variable_listener"
require_relative "listeners/constant_listener"

# Methods & classes
require_relative "listeners/method_listener"
require_relative "listeners/pull_up_method_listener"
require_relative "listeners/extract_predicate_listener"
require_relative "listeners/accessor_listener"
require_relative "listeners/rescue_listener"
require_relative "listeners/super_listener"

# Multi-file
require_relative "listeners/extract_include_file_listener"

# Operators & blocks
require_relative "listeners/tap_listener"
require_relative "listeners/logical_operator_listener"
require_relative "listeners/raise_listener"

# RSpec
require_relative "listeners/rspec_let_listener"

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
    #
    # NOTE: CodeActions#initialize does not receive global_state, so we read it
    # from Addon.global_state — a class-level reference set during activation.
    module CodeActionsExtension
      def perform
        actions = super || []
        actions.concat(
          RubyLsp::Refactor::Addon.refactor_actions_for(
            @document,
            @range,
            RubyLsp::Refactor::Addon.global_state,
          ),
        )
        actions
      end
    end

    class Addon < ::RubyLsp::Addon
      # Class-level accessor so CodeActionsExtension can reach global_state
      # without being injected into CodeActions#initialize.
      class << self
        attr_accessor :global_state
      end

      # Called once when the language server activates this add-on.
      def activate(global_state, _message_queue)
        Addon.global_state = global_state

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
      def self.refactor_actions_for(document, range, global_state = nil)
        return [] unless document.is_a?(RubyLsp::RubyDocument)
        return [] if document.source.empty?

        cursor_range = Interface::Range.new(
          start: Interface::Position.new(
            line: range.dig(:start, :line),
            character: range.dig(:start, :character)
          ),
          end: Interface::Position.new(
            line: range.dig(:end, :line),
            character: range.dig(:end, :character)
          )
        )

        node_context     = NodeContext.new(document.uri.to_s, cursor_range)
        response_builder = RubyLsp::ResponseBuilders::CollectionResponseBuilder.new
        dispatcher       = Prism::Dispatcher.new

        ConditionalListener.new(response_builder, node_context, dispatcher)
        EarlyReturnListener.new(response_builder, node_context, dispatcher)
        StringListener.new(response_builder, node_context, dispatcher)
        StringArrayListener.new(response_builder, node_context, dispatcher)
        StringFreezeListener.new(response_builder, node_context, dispatcher)
        ArrayListener.new(response_builder, node_context, dispatcher)
        HashListener.new(response_builder, node_context, dispatcher)
        EnumerableListener.new(response_builder, node_context, dispatcher)
        VariableListener.new(response_builder, node_context, dispatcher)
        ConstantListener.new(response_builder, node_context, dispatcher)
        MethodListener.new(response_builder, node_context, dispatcher)
        PullUpMethodListener.new(response_builder, node_context, dispatcher, document, global_state)
        ExtractPredicateListener.new(response_builder, node_context, dispatcher)
        AccessorListener.new(response_builder, node_context, dispatcher)
        RescueListener.new(response_builder, node_context, dispatcher)
        SuperListener.new(response_builder, node_context, dispatcher)
        ExtractIncludeFileListener.new(response_builder, node_context, dispatcher)
        TapListener.new(response_builder, node_context, dispatcher)
        LogicalOperatorListener.new(response_builder, node_context, dispatcher)
        RaiseListener.new(response_builder, node_context, dispatcher)
        RspecLetListener.new(response_builder, node_context, dispatcher)

        dispatcher.dispatch(document.ast)
        response_builder.response
      rescue StandardError
        []
      end
    end
  end
end
