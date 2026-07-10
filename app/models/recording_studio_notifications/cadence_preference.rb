# frozen_string_literal: true

module RecordingStudioNotifications
  class CadencePreference < ApplicationRecord
    self.table_name = "recording_studio_notifications_cadence_preferences"

    belongs_to :recipient, polymorphic: true

    validates :recipient, :notification_type, :cadence, presence: true
    validates :notification_type, uniqueness: { scope: %i[recipient_type recipient_id] }
    validate :registered_notification_type
    validate :allowed_cadence

    scope :for_recipient, ->(recipient) { where(recipient: recipient) }

    class << self
      def cadence_for(recipient:, notification_type:, default: nil)
        preference = find_by(recipient: recipient, notification_type: notification_type.to_s)
        preference&.cadence&.to_sym || default
      end

      def set!(recipient:, notification_type:, cadence:)
        preference = find_or_initialize_by(
          recipient: recipient,
          notification_type: notification_type.to_s
        )
        preference.cadence = cadence.to_s
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

    def allowed_cadence
      return if cadence.blank? || !type_definition
      return if type_definition.allowed_cadences.include?(cadence.to_sym)

      errors.add(:cadence, "is not allowed for this notification type")
    end
  end
end
