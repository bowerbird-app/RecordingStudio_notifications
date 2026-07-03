# frozen_string_literal: true

module RecordingStudioNotifications
  class Preference < ApplicationRecord
    self.table_name = "recording_studio_notifications_preferences"

    belongs_to :recipient, polymorphic: true

    validates :recipient, :notification_type, :channel, presence: true
    validates :enabled, inclusion: { in: [true, false] }
    validates :channel, uniqueness: { scope: %i[recipient_type recipient_id notification_type] }
    validate :registered_notification_type
    validate :available_optional_channel

    scope :for_recipient, ->(recipient) { where(recipient: recipient) }
    scope :for_type, ->(notification_type) { where(notification_type: notification_type.to_s) }

    class << self
      def enabled_for?(recipient:, notification_type:, channel:, default: true)
        preference = find_by(
          recipient: recipient,
          notification_type: notification_type.to_s,
          channel: channel.to_s
        )
        preference ? preference.enabled? : default
      end

      def set!(recipient:, notification_type:, channel:, enabled:)
        preference = find_or_initialize_by(
          recipient: recipient,
          notification_type: notification_type.to_s,
          channel: channel.to_s
        )
        preference.enabled = ActiveModel::Type::Boolean.new.cast(enabled)
        preference.save!
        preference
      end
    end

    private

    def type_definition
      @type_definition ||= RecordingStudioNotifications.notification_types[notification_type]
    end

    def registered_notification_type
      return if notification_type.blank?
      return if type_definition

      errors.add(:notification_type, "is not registered")
    end

    def available_optional_channel
      return if channel.blank? || !type_definition

      channel_key = channel.to_s.to_sym
      return if type_definition.optional_channels.include?(channel_key)

      errors.add(:channel, "must be an available optional channel")
    end
  end
end
