# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Emits block-style toggle actions on any CallNode whose block is a
    # BlockNode (i.e. not a bare proc/lambda literal).
    #
    # Emitted actions
    # ───────────────
    # 1. Convert to do…end
    #      receiver.method { |x| body }
    #      →
    #      receiver.method do |x|
    #        body
    #      end
    #
    # 2. Convert to brace block
    #      receiver.method do |x|
    #        body
    #      end
    #      →
    #      receiver.method { |x| body }
    #
    # Convention: multi-statement brace blocks are always expanded to do…end.
    # Single-statement do…end blocks are collapsed to brace style.
    class BlockStyleListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless node_covers_cursor?(node)

        block = node.block
        return unless block.is_a?(Prism::BlockNode)

        if brace_block?(block)
          emit_to_do_end(node, block)
        elsif single_statement_body?(block)
          emit_to_brace(node, block)
        end
      rescue StandardError
        nil
      end

      private

      def brace_block?(block)
        block.opening_loc.slice == "{"
      end

      def single_statement_body?(block)
        block.body&.body&.length == 1
      end

      # ── brace → do…end ──────────────────────────────────────────────────────

      def emit_to_do_end(call_node, block)
        indent      = indent_for(call_node)
        params_src  = params_string(block)
        body_lines  = block.body.body.map { |s| "#{indent}  #{s.location.slice.strip}" }.join("\n")

        new_block = " do#{params_src}\n#{body_lines}\n#{indent}end"
        new_text  = call_without_block(call_node) + new_block

        @response_builder << Interface::CodeAction.new(
          title: "Convert to do…end block",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(call_node, new_text)
        )
      end

      # ── do…end → brace ──────────────────────────────────────────────────────

      def emit_to_brace(call_node, block)
        params_src = params_string(block)
        body_src   = block.body.body.first.location.slice.strip

        new_block = " {#{params_src} #{body_src} }"
        new_text  = call_without_block(call_node) + new_block

        @response_builder << Interface::CodeAction.new(
          title: "Convert to brace block",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(call_node, new_text)
        )
      end

      # ── helpers ──────────────────────────────────────────────────────────────

      # Returns the block parameters string including pipes, e.g. " |x, y|",
      # or an empty string when the block takes no parameters.
      def params_string(block)
        return "" unless block.parameters

        " #{block.parameters.location.slice}"
      end

      # Returns the source of the call node up to (but not including) the block.
      # Works by slicing from the call's start to the block's start.
      def call_without_block(call_node)
        call_src   = call_node.location.slice
        block_src  = call_node.block.location.slice
        # Remove the block suffix (and any whitespace before it) from the call.
        call_src[0, call_src.length - block_src.length].rstrip
      end
    end
  end
end
