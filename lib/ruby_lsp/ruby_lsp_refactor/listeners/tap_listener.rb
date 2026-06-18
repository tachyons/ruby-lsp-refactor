# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Offers "Convert to tap" when the cursor is inside a method whose body
    # is a sequence of calls on the same receiver followed by a bare return
    # of that receiver.
    #
    # From "Encourage use of Object#tap" in Refactoring Rails: groups
    # operations on the same object into a tap block and removes the explicit
    # return at the end.
    #
    # Input (cursor anywhere inside the method):
    #   def do_something
    #     obj.do_first_thing
    #     obj.do_second_thing
    #     obj.do_third_thing
    #     obj
    #   end
    #
    # Output:
    #   def do_something
    #     obj.tap do |o|
    #       o.do_first_thing
    #       o.do_second_thing
    #       o.do_third_thing
    #     end
    #   end
    #
    # Eligibility:
    #   - Method body has at least two statements.
    #   - All statements except the last are CallNodes whose receiver is a
    #     variable_call (bare local variable or method with no receiver).
    #   - All those receivers share the same name.
    #   - The last statement is a bare variable_call with the same name.
    class TapListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        dispatcher.register(self, :on_def_node_enter)
      end

      def on_def_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless (receiver_name = tap_eligible?(node))

        emit_convert_to_tap(node, receiver_name)
      rescue StandardError
        nil
      end

      private

      # Returns the shared receiver name if the method body is tap-eligible,
      # or nil otherwise.
      def tap_eligible?(def_node)
        body = def_node.body
        return false unless body.is_a?(Prism::StatementsNode)

        stmts = body.body
        return false unless stmts.length >= 2

        last = stmts.last
        calls = stmts[0..-2]

        # Last statement must be a bare variable_call.
        return false unless last.is_a?(Prism::CallNode) && last.variable_call?

        receiver_name = last.name

        # Every preceding statement must be a non-variable call whose receiver
        # is a variable_call with the same name.
        all_match = calls.all? do |c|
          c.is_a?(Prism::CallNode) &&
            !c.variable_call? &&
            c.receiver.is_a?(Prism::CallNode) &&
            c.receiver.variable_call? &&
            c.receiver.name == receiver_name
        end

        receiver_name if all_match
      end

      def emit_convert_to_tap(def_node, receiver_name)
        body_indent = "#{indent_for(def_node)}  "
        tap_indent  = "#{body_indent}  "

        stmts = def_node.body.body
        calls = stmts[0..-2]

        # Rebuild each call as `o.method(args)` using the slice after the receiver.
        tap_lines = calls.map do |c|
          full      = c.location.slice.strip
          recv_src  = c.receiver.location.slice.strip
          # Everything after "recv." is the method call part.
          method_part = full[(recv_src.length + 1)..]
          "#{tap_indent}o.#{method_part}"
        end.join("\n")

        new_body = "#{body_indent}#{receiver_name}.tap do |o|\n" \
                   "#{tap_lines}\n" \
                   "#{body_indent}end"

        # Replace the entire method body (all statements) with the tap block.
        body_node  = def_node.body
        body_range = Interface::Range.new(
          start: Interface::Position.new(
            line: body_node.location.start_line - 1,
            character: body_node.location.start_column
          ),
          end: Interface::Position.new(
            line: body_node.location.end_line - 1,
            character: body_node.location.end_column
          )
        )

        edit = Interface::TextEdit.new(range: body_range, new_text: new_body)

        @response_builder << Interface::CodeAction.new(
          title: "Convert to tap",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: multi_edit_workspace_edit([edit])
        )
      end
    end
  end
end
