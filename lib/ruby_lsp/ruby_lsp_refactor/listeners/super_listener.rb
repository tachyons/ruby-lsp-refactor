# frozen_string_literal: true

require_relative "../support/node_helpers"

module RubyLsp
  module Refactor
    # Converts a bare `super` (ForwardingSuperNode) inside a def that has
    # parameters into an explicit `super(param1, param2, ...)`.
    #
    # Input (cursor on `super`):
    #   def initialize(name, age)
    #     super
    #   end
    #
    # Output:
    #   def initialize(name, age)
    #     super(name, age)
    #   end
    #
    # Bare `super` forwards all arguments implicitly; making them explicit
    # is safer when the method signature changes over time.
    class SuperListener
      include RubyLsp::Requests::Support::Common
      include Support::NodeHelpers

      def initialize(response_builder, node_context, dispatcher)
        @response_builder = response_builder
        @node_context     = node_context

        @current_def = nil

        dispatcher.register(
          self,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_forwarding_super_node_enter
        )
      end

      def on_def_node_enter(node)
        @current_def = node
      end

      def on_def_node_leave(_node)
        @current_def = nil
      end

      def on_forwarding_super_node_enter(node)
        return unless node_covers_cursor?(node)
        return unless @current_def
        return unless has_params?(@current_def)

        emit_explicit_super(node, @current_def)
      rescue StandardError
        nil
      end

      private

      def has_params?(def_node)
        params = def_node.parameters
        return false unless params

        params.requireds.any? || params.optionals.any? || params.keywords.any?
      end

      def emit_explicit_super(super_node, def_node)
        param_names = collect_param_names(def_node.parameters)
        new_text    = "#{indent_for(super_node)}super(#{param_names.join(", ")})"

        @response_builder << Interface::CodeAction.new(
          title: "Convert to explicit super(#{param_names.join(", ")})",
          kind: Constant::CodeActionKind::REFACTOR_REWRITE,
          edit: single_edit_workspace_edit(super_node, new_text)
        )
      end

      def collect_param_names(params_node)
        names = []
        params_node.requireds.each do |p|
          names << p.name.to_s if p.respond_to?(:name)
        end
        params_node.optionals.each do |p|
          names << p.name.to_s if p.respond_to?(:name)
        end
        params_node.keywords.each do |p|
          # keyword params: `name:` — pass as `name: name`
          kw_name = p.name.to_s.delete_suffix(":")
          names << "#{kw_name}: #{kw_name}"
        end
        names
      end
    end
  end
end
