# frozen_string_literal: true

require_relative "cadence_period"
require_relative "channel_applicability"
require_relative "inbox_flag"
require_relative "notify_attributes"
require_relative "notify_persistence"
require_relative "notify_validation"

module RecordingStudioNotifications
  module Services
    class Notify
      include ChannelApplicability
      include InboxFlag
      include NotifyAttributes
      include NotifyPersistence
      include NotifyValidation

      def self.call(...)
        new(...).call
      end

      def initialize(**attributes)
        apply_notify_attributes(attributes)
      end

      def call
        validate_inputs!
        existing = find_idempotent_notification
        unless existing
          reject_hidden_required_in_app!
          return nil if channel_keys.empty?
        end

        authorize_creation!

        hooks.run(:before_service, self.class, service_payload)
        result = hooks.run_around(:around_service, self) { create_and_deliver!(existing) }
        hooks.run(:after_service, self.class, result)
        result
      end

      private

      def authorize_creation!
        return unless type_definition.creation_action
        return if accessible_action_allowed?(type_definition.creation_action)

        raise RecordingStudioNotifications::Services::NotificationAuthorization::NotAuthorized,
              "not authorized to create #{@notification_type} notifications"
      end

      def accessible_action_allowed?(action)
        return false unless defined?(RecordingStudioAccessible)
        return false unless RecordingStudioAccessible.respond_to?(:authorized_action?)

        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: action,
          recording: resolved_root_recording || @recording,
          context: {
            recipient: @recipient,
            notification_type: @notification_type.to_sym,
            notifiable: @notifiable,
            metadata: @metadata
          }
        )
      end

      def hooks
        RecordingStudioNotifications.configuration.hooks
      end

      def service_payload
        {
          notification_type: @notification_type,
          recipient: @recipient,
          actor: @actor,
          notifiable: @notifiable,
          recording: @recording,
          root_recording: resolved_root_recording,
          channels: channel_keys
        }
      end

      def type_definition
        @type_definition ||= RecordingStudioNotifications.notification_types[@notification_type]
      end

      def find_idempotent_notification
        return if @idempotency_key.blank?

        Notification.find_by(recipient: @recipient, idempotency_key: @idempotency_key)
      end

      def resolved_root_recording
        return nil if type_definition&.scope == :global

        @resolved_root_recording ||= RootResolver.call(
          root_recording: @root_recording,
          recording: @recording,
          recordable: @notifiable
        )
      end

      def deferred_rollup_channel?(_channel)
        effective_cadence != :individual
      end

      def effective_cadence
        @effective_cadence ||= begin
          return :individual unless RecordingStudioNotifications.configuration.rollup_delivery_enabled
          return type_definition.required_cadence if type_definition.required_cadence
          return type_definition.default_cadence unless preference_table_available?

          Preference.cadence_for(
            recipient: @recipient,
            notification_type: @notification_type,
            default: type_definition.default_cadence
          )
        end
      end

      def recipient_time_zone
        @recipient.try(:time_zone).presence || Time.zone || "UTC"
      end

      def preference_table_available?
        defined?(RecordingStudioNotifications::Preference) && RecordingStudioNotifications::Preference.table_exists?
      end

      def channel_keys
        @channel_keys ||= begin
          required = type_definition.required_channels
          optional = selected_optional_channels
          selected = (optional + required).uniq
          enabled = selected.select { |channel| required.include?(channel) || preference_enabled?(channel, default: true) }
          without_hidden_in_app(
            enabled.select { |channel| channel_applicable?(channel) || required.include?(channel) }
          )
        end
      end

      def consistent_root_scope?
        return true if type_definition.scope == :global

        RootResolver.consistent?(
          root_recording: resolved_root_recording,
          recording: @recording,
          recordable: @notifiable
        )
      end
    end
  end
end
