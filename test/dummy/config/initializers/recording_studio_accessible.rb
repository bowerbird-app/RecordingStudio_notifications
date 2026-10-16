# frozen_string_literal: true

# Dummy app authorization wiring for RecordingStudio Accessible demonstrations.
if defined?(RecordingStudioAccessible)
  RecordingStudioAccessible.configure do |config|
    config.access_actor_types = ["User"]
  end

  # Compatibility adapter: expose action-based APIs expected by notifications engine.
  unless RecordingStudioAccessible.respond_to?(:authorized_action?)
    RecordingStudioAccessible.singleton_class.class_eval do
      def recording_studio_notifications_action_registry
        @recording_studio_notifications_action_registry ||= {}
      end

      def register_action(action, **metadata)
        recording_studio_notifications_action_registry[action.to_sym] ||= metadata
      end

      def action_defined?(action)
        recording_studio_notifications_action_registry.key?(action.to_sym)
      end

      def define_action(action, &block)
        recording_studio_notifications_action_registry[action.to_sym] = block
      end

      def authorized_action?(actor:, action:, recording: nil, context: {}, controller: nil, **)
        action_key = action.to_sym
        policy = recording_studio_notifications_action_registry[action_key]

        if policy
          return policy.call(actor: actor, recording: recording, context: context, controller: controller)
        end

        return true if recording.blank?

        begin
          authorized?(actor: actor, recording: recording, role: :view)
        rescue StandardError
          false
        end
      end
    end
  end

  if RecordingStudioAccessible.respond_to?(:define_action)
    define_unless_present = lambda do |action, &block|
      next if RecordingStudioAccessible.respond_to?(:action_defined?) && RecordingStudioAccessible.action_defined?(action)

      RecordingStudioAccessible.define_action(action, &block)
    end

    define_unless_present.call(:view_notifications) do |actor:, context: {}, **|
      recipient = context[:recipient]
      actor.present? && recipient.present? && actor.class.name == recipient.class.name && actor.id.to_s == recipient.id.to_s
    end

    define_unless_present.call(:"recording_studio_notifications.manage_preferences") do |actor:, context: {}, **|
      recipient = context[:recipient]
      actor.present? && recipient.present? && actor.class.name == recipient.class.name && actor.id.to_s == recipient.id.to_s
    end
  end
end
