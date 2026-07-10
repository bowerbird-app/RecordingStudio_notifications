# frozen_string_literal: true

module RecordingStudioNotifications
  class DigestsController < ApplicationController
    PER_PAGE = 25

    layout "recording_studio_notifications/blank"

    before_action :set_recipient
    before_action :set_digest

    def show
      return unless authorize_notifications!(recipient: @recipient, recording: @digest.root_recording)
      return head :forbidden unless digest_visible?

      @page = current_page
      @notifications, @has_next_page = visible_notifications_page(source_notifications)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    private

    def set_recipient
      @recipient = current_notifications_actor
      head :unauthorized unless @recipient
    end

    def set_digest
      @digest = NotificationDigest.where(recipient: @recipient).find(params[:id])
    end

    def source_notifications
      @digest.source_notifications.active.newest_first
    end

    def digest_visible?
      source_notifications.find_each.any? { |notification| visible_notification?(notification) }
    end

    def visible_notifications_page(notifications_scope)
      visible_offset = (@page - 1) * PER_PAGE
      loaded_visible_count = 0
      collected = []
      database_offset = 0
      batch_size = PER_PAGE * 4

      loop do
        batch = notifications_scope.offset(database_offset).limit(batch_size).to_a
        break if batch.empty?

        batch.each do |notification|
          next unless visible_notification?(notification)

          if loaded_visible_count < visible_offset
            loaded_visible_count += 1
            next
          end

          collected << notification
          break if collected.size > PER_PAGE
        end

        break if collected.size > PER_PAGE

        database_offset += batch.size
      end

      [collected.first(PER_PAGE), collected.size > PER_PAGE]
    end

    def visible_notification?(notification)
      Services::NotificationAuthorization.visible_notification?(
        actor: current_notifications_actor,
        notification: notification,
        controller: self
      )
    end

    def current_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end
  end
end