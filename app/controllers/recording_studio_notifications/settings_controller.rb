# frozen_string_literal: true

module RecordingStudioNotifications
  class SettingsController < ApplicationController
    layout "recording_studio_notifications/blank"

    before_action :set_recipient
    before_action :authorize_settings

    def show
      @notification_types = configurable_notification_types
      @preferences = preference_map
    end

    def update
      preference_params.each do |type_key, channels|
        channels.each do |channel, enabled|
          Preference.set!(
            recipient: @recipient,
            notification_type: type_key,
            channel: channel,
            enabled: enabled
          )
        end
      end

      redirect_to settings_path, notice: "Notification preferences updated."
    rescue ActiveRecord::RecordInvalid, ArgumentError
      @notification_types = configurable_notification_types
      @preferences = preference_map
      flash.now[:alert] = "Notification preferences could not be updated."
      render :show, status: :unprocessable_entity
    end

    private

    def set_recipient
      @recipient = current_notifications_actor
      head :unauthorized unless @recipient
    end

    def authorize_settings
      authorize_preferences!(recipient: @recipient)
    end

    def configurable_notification_types
      RecordingStudioNotifications.notification_types.values.select { |type| type.optional_channels.any? }
    end

    def preference_map
      Preference.for_recipient(@recipient).each_with_object({}) do |preference, map|
        map[[preference.notification_type.to_sym, preference.channel.to_sym]] = preference.enabled?
      end
    end

    def preference_params
      raw_preferences = params.fetch(:preferences, {})
      return {} unless raw_preferences.respond_to?(:to_unsafe_h)

      submitted = raw_preferences.to_unsafe_h
      configurable_notification_types.each_with_object({}) do |type, allowed|
        channels = submitted[type.key.to_s]
        next unless channels.respond_to?(:to_h)

        allowed_channels = type.optional_channels.each_with_object({}) do |channel, channel_values|
          next unless channels.key?(channel.to_s)

          channel_values[channel.to_s] = channels[channel.to_s]
        end
        allowed[type.key.to_s] = allowed_channels if allowed_channels.any?
      end
    end
  end
end
