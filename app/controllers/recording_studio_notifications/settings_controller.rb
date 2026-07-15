# frozen_string_literal: true

module RecordingStudioNotifications
  class SettingsController < ApplicationController
    layout "recording_studio_notifications/blank"

    helper_method :channel_configurable?, :cadence_selectable?, :rollup_delivery_enabled?

    before_action :set_recipient
    before_action :authorize_settings

    def show
      prepare_settings_view
    end

    def update
      ApplicationRecord.transaction do
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

        cadence_params.each do |type_key, cadence|
          Preference.set_cadence!(
            recipient: @recipient,
            notification_type: type_key,
            cadence: cadence
          )
        end
      end

      redirect_to settings_path, notice: "Notification preferences updated."
    rescue ActiveRecord::RecordInvalid, ArgumentError
      prepare_settings_view
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
      RecordingStudioNotifications.notification_types.values.select do |type|
        next false if type.key == :generic

        channel_configurable?(type) || (rollup_delivery_enabled? && (cadence_selectable?(type) || type.required_cadence.present?))
      end
    end

    def prepare_settings_view
      @notification_type_groups = grouped_notification_types
      @preferences = preference_map
      @channel_select_options = channel_select_options_map
      @selected_channels = selected_channels_map
      @cadence_select_options = cadence_select_options_map
      @selected_cadences = selected_cadences_map
    end

    def grouped_notification_types
      configurable_notification_types
        .group_by { |type| notification_type_category(type) }
        .sort_by { |category, _types| category.to_s }
        .to_h
    end

    def notification_type_category(type)
      return type.category if type.respond_to?(:category) && type.category.present?

      :general
    end

    def flat_notification_types
      @flat_notification_types ||= @notification_type_groups.values.flatten
    end

    def channel_select_options_map
      flat_notification_types.each_with_object({}) do |type, map|
        options = Array(type.available_channels).map do |channel|
          [channel_option_label(type, channel), channel.to_s, { disabled: type.required_channels.include?(channel) }]
        end

        options.unshift(%w[None __none__]) if type.required_channels.empty?

        map[type.key] = options
      end
    end

    def selected_channels_map
      flat_notification_types.each_with_object({}) do |type, map|
        map[type.key] = type.optional_channels.select do |channel|
          preference_enabled?(type, channel)
        end.map(&:to_s)
      end
    end

    def cadence_select_options_map
      flat_notification_types.each_with_object({}) do |type, map|
        next unless cadence_selectable?(type)

        map[type.key] = type.allowed_cadences.map { |cadence| [cadence.to_s.humanize, cadence.to_s] }
      end
    end

    def selected_cadences_map
      flat_notification_types.each_with_object({}) do |type, map|
        next unless cadence_selectable?(type)

        map[type.key] = Preference.cadence_for(
          recipient: @recipient,
          notification_type: type.key,
          default: type.default_cadence
        ).to_s
      end
    end

    def preference_enabled?(type, channel)
      @preferences.fetch([type.key, channel], Array(type.default_channels).include?(channel))
    end

    def channel_option_label(type, channel)
      return channel.to_s.humanize unless type.required_channels.include?(channel)

      "#{channel.to_s.humanize} (required)"
    end

    def preference_map
      Preference.for_recipient(@recipient).each_with_object({}) do |preference, map|
        next if preference.channel.blank?

        map[[preference.notification_type.to_sym, preference.channel.to_sym]] = preference.enabled?
      end
    end

    def preference_params
      return {} unless params.key?(:preferences)

      raw_preferences = params[:preferences]
      return {} unless raw_preferences.respond_to?(:to_unsafe_h)

      submitted = raw_preferences.to_unsafe_h
      configurable_notification_types.each_with_object({}) do |type, allowed|
        selected_channels = Array(submitted[type.key.to_s]).flatten.map(&:to_s).reject(&:blank?)
        selected_channels = [] if selected_channels.include?("__none__")

        allowed_channels = type.optional_channels.each_with_object({}) do |channel, channel_values|
          channel_values[channel.to_s] = selected_channels.include?(channel.to_s) ? "1" : "0"
        end
        allowed[type.key.to_s] = allowed_channels if allowed_channels.any?
      end
    end

    def cadence_params
      return {} unless params.key?(:cadences)

      raw_cadences = params[:cadences]
      return {} unless raw_cadences.respond_to?(:to_unsafe_h)

      submitted = raw_cadences.to_unsafe_h
      configurable_notification_types.each_with_object({}) do |type, allowed|
        next unless cadence_selectable?(type)

        cadence = submitted[type.key.to_s].to_s.strip
        allowed[type.key.to_s] = cadence if cadence.present?
      end
    end

    def channel_configurable?(type)
      type.available_channels.present? && (type.optional_channels.any? || type.required_channels.any?)
    end

    def cadence_selectable?(type)
      rollup_delivery_enabled? && type.required_cadence.nil? && type.allowed_cadences.size > 1
    end

    def rollup_delivery_enabled?
      RecordingStudioNotifications.configuration.rollup_delivery_enabled
    end
  end
end
