# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Preferences
      TITLE = "Show notification preferences"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: ToolDescriptions::PREFERENCES,
        tags: ["Notifications"]
      }.freeze

      def self.call(context)
        recipient = Gate.authorize_preferences!(context)
        {
          records: Preference.for_recipient(recipient).map { |row| Serialize.channel_preference(row) }
        }
      end
    end

    class UpdatePreferences
      TITLE = "Update notification preferences"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: ToolDescriptions::UPDATE_PREFERENCES,
        tags: ["Notifications"]
      }.freeze
      INPUT_CONTRACT = {
        reject_unknown: true,
        fields: {
          notification_type: {
            type: :string,
            required: true,
            description: ToolDescriptions::NOTIFICATION_TYPE
          },
          channel: {
            type: :string,
            required: false,
            description: ToolDescriptions::CHANNEL
          },
          enabled: {
            type: :boolean,
            required: false,
            description: ToolDescriptions::ENABLED
          },
          cadence: {
            type: :string,
            required: false,
            description: ToolDescriptions::CADENCE
          }
        }
      }.freeze

      def self.call(context)
        recipient = Gate.authorize_preferences!(context)
        attributes = Gate.request_payload(context)
        notification_type = attributes[:notification_type]
        raise RecordingStudioApi::InvalidActionInputError, "notification_type is required" if notification_type.blank?

        write_channel!(recipient, notification_type, attributes)
        write_cadence!(recipient, notification_type, attributes)
        {
          records: Preference.for_recipient(recipient).map { |row| Serialize.channel_preference(row) }
        }
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        raise RecordingStudioApi::InvalidActionInputError, e.message
      end

      def self.write_channel!(recipient, notification_type, attributes)
        channel = attributes[:channel]
        return if channel.blank?

        Preference.set!(
          recipient: recipient,
          notification_type: notification_type,
          channel: channel,
          enabled: attributes[:enabled]
        )
      end

      def self.write_cadence!(recipient, notification_type, attributes)
        cadence = attributes[:cadence]
        return if cadence.blank?

        Preference.set_cadence!(
          recipient: recipient,
          notification_type: notification_type,
          cadence: cadence
        )
      end
      private_class_method :write_channel!, :write_cadence!
    end
  end
end
