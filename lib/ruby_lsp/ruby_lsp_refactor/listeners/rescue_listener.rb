# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Wrap body in rescue" on any DefNode whose body does not already
    # contain a rescue clause.
    #
    # Input (cursor anywhere inside the def):
    #   def call
    #     do_thing
    #     another_thing
    #   end
    #
    # Output:
    #   def call
    #     do_thing
    #     another_thing
    #   rescue StandardError => e
    #     raise
    #   end
    #
    # The generated rescue clause uses `raise` to re-raise by default so the
    # developer can fill in the actual error handling without accidentally
    # swallowing exceptions.
    class RescueListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_def_node_enter)
      end

      def on_def_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless node.body.is_a?(Prism::StatementsNode) # already has rescue if BeginNode
        return if node.body.body.empty?

        emit_wrap_rescue(node)
      rescue StandardError
        nil
      end

      private

      def emit_wrap_rescue(def_node)
        indent      = indent_for(def_node)
        body_indent = "#{indent}  "

        # Preserve the existing body lines verbatim.
        body_src = def_node.body.body
                           .map { |s| "#{body_indent}#{s.location.slice.strip}" }
                           .join("\n")

        # Reconstruct the full def with a rescue clause appended before `end`.
        def_header = build_def_header(def_node)
        new_text   = <<~RUBY.chomp
          #{indent}#{def_header}
          #{body_src}
          #{body_indent}rescue StandardError => e
          #{body_indent}  raise
          #{indent}end
        RUBY

        @response_builder << Interface::CodeAction.new(
          title: "Wrap body in rescue",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(def_node, new_text)
        )
      end

      # Reconstructs the `def name(params)` header line from the node's locations.
      def build_def_header(node)
        src = node.location.slice
        # Take everything up to and including the closing paren (or method name
        # when there are no params), stopping before the newline.
        src.lines.first.rstrip
      end
    end
  end
end
