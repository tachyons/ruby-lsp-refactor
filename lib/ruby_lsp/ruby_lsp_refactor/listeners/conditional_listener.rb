# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Handles all conditional-related code actions by listening to IfNode and
    # UnlessNode events from the Prism dispatcher.
    #
    # Emitted actions
    # ───────────────
    # 1. Convert to post-conditional
    #      if cond          →   body if cond
    #        body
    #      end
    #
    # 2. Convert to block if / block unless
    #      body if cond     →   if cond
    #                             body
    #                           end
    #
    # 3. Toggle if ↔ unless
    #      if cond  →  unless cond   (and vice-versa, no else/elsif)
    #
    # 4. Invert if/else
    #      if cond          →   if !cond
    #        then_body            else_body
    #      else             →   else
    #        else_body            then_body
    #      end              →   end
    class ConditionalListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      # @param response_builder [RubyLsp::ResponseBuilders::CollectionResponseBuilder]
      # @param node_context     [RubyLsp::NodeContext]
      # @param dispatcher       [Prism::Dispatcher]
      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_if_node_enter, :on_unless_node_enter)
      end

      # ── dispatcher callbacks ────────────────────────────────────────────────

      def on_if_node_enter(node)
        return unless node_covers_cursor?(node)

        emit_to_post_conditional(node)  if block_if_convertible_to_post?(node)
        emit_to_block_if(node)          if post_if_convertible_to_block?(node)
        emit_toggle_to_unless(node)     if toggleable_if?(node)
        emit_invert_if_else(node)       if invertible_if_else?(node)
      rescue StandardError
        nil
      end

      def on_unless_node_enter(node)
        return unless node_covers_cursor?(node)

        emit_to_post_unless(node)   if block_unless_convertible_to_post?(node)
        emit_to_block_unless(node)  if post_unless_convertible_to_block?(node)
        emit_toggle_to_if(node)     if toggleable_unless?(node)
      rescue StandardError
        nil
      end

      private

      # ── predicate helpers ───────────────────────────────────────────────────

      # block `if` with a single-statement body and no else/elsif
      def block_if_convertible_to_post?(node)
        node.end_keyword_loc &&
          node.subsequent.nil? &&
          node.statements&.body&.length == 1
      end

      # post-conditional `if` (no `end` keyword)
      def post_if_convertible_to_block?(node)
        node.end_keyword_loc.nil?
      end

      # block `if` with no else/elsif — can flip to `unless`
      def toggleable_if?(node)
        node.end_keyword_loc && node.subsequent.nil?
      end

      # block `if` with exactly one else branch (no elsif) — can invert
      def invertible_if_else?(node)
        node.end_keyword_loc &&
          node.subsequent.is_a?(Prism::ElseNode) &&
          node.statements&.body&.length&.positive? &&
          node.subsequent.statements&.body&.length&.positive?
      end

      # block `unless` with a single-statement body and no else
      def block_unless_convertible_to_post?(node)
        node.end_keyword_loc &&
          unless_else_clause(node).nil? &&
          node.statements&.body&.length == 1
      end

      # post-conditional `unless` (no `end` keyword)
      def post_unless_convertible_to_block?(node)
        node.end_keyword_loc.nil?
      end

      # block `unless` with no else — can flip to `if`
      def toggleable_unless?(node)
        node.end_keyword_loc && unless_else_clause(node).nil?
      end

      # `UnlessNode#consequent` is deprecated in Prism >= 1.x; use `else_clause`.
      def unless_else_clause(node)
        node.respond_to?(:else_clause) ? node.else_clause : node.consequent
      end

      # ── emitters ────────────────────────────────────────────────────────────

      # 1a. block if → post-conditional if
      def emit_to_post_conditional(node)
        indent   = indent_for(node)
        cond_src = node.predicate.location.slice.strip
        body_src = node.statements.body.first.location.slice.strip
        new_text = "#{indent}#{body_src} if #{cond_src}"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to post-conditional",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 1b. block unless → post-conditional unless
      def emit_to_post_unless(node)
        indent   = indent_for(node)
        cond_src = node.predicate.location.slice.strip
        body_src = node.statements.body.first.location.slice.strip
        new_text = "#{indent}#{body_src} unless #{cond_src}"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to post-conditional",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 2a. post-conditional if → block if
      def emit_to_block_if(node)
        indent   = indent_for(node)
        cond_src = node.predicate.location.slice.strip
        body_src = node.statements.body.first.location.slice.strip
        new_text = "#{indent}if #{cond_src}\n#{indent}  #{body_src}\n#{indent}end"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to block if",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 2b. post-conditional unless → block unless
      def emit_to_block_unless(node)
        indent   = indent_for(node)
        cond_src = node.predicate.location.slice.strip
        body_src = node.statements.body.first.location.slice.strip
        new_text = "#{indent}unless #{cond_src}\n#{indent}  #{body_src}\n#{indent}end"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to block unless",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 3a. if → unless  (strips leading `!` from predicate when present)
      def emit_toggle_to_unless(node)
        indent   = indent_for(node)
        cond_src = stripped_negation(node.predicate)
        body_src = node.statements.body.map { |s| "#{indent}  #{s.location.slice.strip}" }.join("\n")
        new_text = "#{indent}unless #{cond_src}\n#{body_src}\n#{indent}end"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to unless",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 3b. unless → if  (strips leading `!` from predicate when present)
      def emit_toggle_to_if(node)
        indent   = indent_for(node)
        cond_src = stripped_negation(node.predicate)
        body_src = node.statements.body.map { |s| "#{indent}  #{s.location.slice.strip}" }.join("\n")
        new_text = "#{indent}if #{cond_src}\n#{body_src}\n#{indent}end"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to if",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # 4. Invert if/else — swap branches, negate predicate
      def emit_invert_if_else(node)
        indent    = indent_for(node)
        cond_src  = negated_predicate(node.predicate)
        then_body = node.statements.body.map { |s| "#{indent}  #{s.location.slice.strip}" }.join("\n")
        else_body = node.subsequent.statements.body.map { |s| "#{indent}  #{s.location.slice.strip}" }.join("\n")
        new_text  = "#{indent}if #{cond_src}\n#{else_body}\n#{indent}else\n#{then_body}\n#{indent}end"

        @response_builder << Interface::CodeAction.new(
          title: "Invert if/else",
          kind:  Constant::CodeActionKind::REFACTOR_REWRITE,
          edit:  single_edit_workspace_edit(node, new_text),
        )
      end

      # ── predicate negation helpers ──────────────────────────────────────────

      # Returns the source of the predicate with a leading `!` stripped.
      # If the predicate is not a `!` call, returns it unchanged (used for
      # toggle: `if !x` → `unless x`, `unless !x` → `if x`).
      def stripped_negation(predicate)
        if bang_call?(predicate)
          predicate.receiver.location.slice.strip
        else
          predicate.location.slice.strip
        end
      end

      # Returns a negated form of the predicate source:
      #   - `!x`  → `x`   (double-negation cancels)
      #   - `x`   → `!x`
      def negated_predicate(predicate)
        if bang_call?(predicate)
          predicate.receiver.location.slice.strip
        else
          "!#{predicate.location.slice.strip}"
        end
      end

      # Returns true when +node+ is a `!` unary call (CallNode with name :!).
      def bang_call?(node)
        node.is_a?(Prism::CallNode) && node.name == :! && node.receiver
      end
    end
  end
end
