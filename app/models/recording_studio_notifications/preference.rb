# frozen_string_literal: true

module RecordingStudioNotifications
  class Preference < ApplicationRecord
    self.table_name = "recording_studio_notifications_preferences"

    belongs_to :recipient, polymorphic: true

    validates :recipient, :notification_type, presence: true
    validates :enabled, inclusion: { in: [true, false] }, if: :channel_preference?
    validates :channel, uniqueness: { scope: %i[recipient_type recipient_id notification_type] }, if: :channel_preference?
    validate :registered_notification_type
    validate :valid_preference_shape
    validate :available_optional_channel
    validate :allowed_cadence

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
        raise ArgumentError, "channel is required" if channel.blank?

        preference = find_or_initialize_by(
          recipient: recipient,
          notification_type: notification_type.to_s,
          channel: channel.to_s
        )
        preference.enabled = ActiveModel::Type::Boolean.new.cast(enabled)
        preference.save!
        preference
      end

      def set_cadence!(recipient:, notification_type:, cadence:)
        type = notification_type_definition!(notification_type)
        normalized_cadence = cadence.to_s.strip.to_sym

        unless type.allowed_cadences.include?(normalized_cadence)
          raise ArgumentError, "cadence #{normalized_cadence.inspect} is not allowed for #{type.key.inspect}"
        end

        scope = where(recipient: recipient, notification_type: type.key.to_s, channel: nil)
        return scope.destroy_all if normalized_cadence == type.default_cadence

        preference = scope.first_or_initialize
        preference.cadence = normalized_cadence
        preference.enabled = nil
        preference.save!
        preference
      end

      def cadence_for(recipient:, notification_type:, default:)
        type = notification_type_definition!(notification_type)
        return type.required_cadence if type.required_cadence

        preference = find_by(recipient: recipient, notification_type: type.key.to_s, channel: nil)
        preference ? preference.cadence.to_sym : default.to_sym
      end

      private

      def notification_type_definition!(notification_type)
        RecordingStudioNotifications.notification_types.fetch(notification_type)
      end
    end

    private

    def channel_preference?
      channel.present?
    end

    def cadence_preference?
      channel.nil? && cadence.present?
    end

    def type_definition
      @type_definition ||= RecordingStudioNotifications.notification_types[notification_type]
    end

    def registered_notification_type
      return if notification_type.blank?
      return if type_definition

      errors.add(:notification_type, "is not registered")
    end

    def available_optional_channel
      return unless channel_preference? && type_definition

      channel_key = channel.to_s.to_sym
      return if type_definition.optional_channels.include?(channel_key)

      errors.add(:channel, "must be an available optional channel")
    end

    def valid_preference_shape
      return if channel_preference? && enabled.in?([true, false]) && cadence.nil?
      return if channel.nil? && enabled.nil? && cadence.present?

      errors.add(:base, "must be either a channel preference or a cadence override")
    end

    def allowed_cadence
      return unless cadence_preference? && type_definition

      cadence_key = cadence.to_s.to_sym
      return if type_definition.allowed_cadences.include?(cadence_key)

      errors.add(:cadence, "is not allowed for this notification type")
    end
  end
end
