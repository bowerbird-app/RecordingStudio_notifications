# frozen_string_literal: true

require_relative "digest_summary_presenter"
require_relative "notify"

module RecordingStudioNotifications
  module Services
    class DigestDelivery
      def self.call(...)
        new(...).call
      end

      def initialize(digest:, at: Time.current)
        @digest = digest
        @at = at
      end

      def call
        summary = nil

        @digest.with_lock do
          @digest.reload
          return unless due_pending_digest?

          unless recipient_eligible?
            @digest.update!(status: "cancelled")
            return
          end

          summary = create_summary!
          @digest.update!(status: "delivered", delivered_at: @at)
        end

        summary
      end

      private

      def due_pending_digest?
        @digest.pending? && @digest.period_ends_at <= @at
      end

      def recipient_eligible?
        NotificationAuthorization.allowed?(
          actor: @digest.recipient,
          recipient: @digest.recipient,
          recording: @digest.root_recording
        )
      end

      def create_summary!
        summary = summary_attributes

        RecordingStudioNotifications.notify(
          notification_type: :generic,
          recipient: @digest.recipient,
          title: summary.fetch(:title),
          body: summary[:body],
          url: summary[:destination],
          metadata: {
            digest_id: @digest.id,
            digest_summary: true,
            digest_icon: summary[:icon]
          },
          root_recording: @digest.root_recording,
          idempotency_key: "digest-summary-#{@digest.id}",
          bypass_digest: true
        )
      end

      def summary_attributes
        presenter = RecordingStudioNotifications.configuration.digest_summary_presenter || DigestSummaryPresenter
        attributes = presenter.call(digest: @digest).symbolize_keys
        attributes.fetch(:title)
        attributes
      end
    end
  end
end