# frozen_string_literal: true

module RecordingStudioNotifications
  class UnsubscribesController < ActionController::Base
    include NotificationsHelper

    helper NotificationsHelper
    helper_method :unsubscribe_title, :unsubscribe_subtitle, :settings_href

    layout "recording_studio_notifications/blank"

    skip_forgery_protection
    before_action :skip_session_cookie

    def show
      assign_unsubscribe
      render :show, status: (@outcome == :missing ? :not_found : :ok)
    end

    def update
      assign_unsubscribe
      return render :show, status: refusal_status if refusal?

      turn_channel_off! if @outcome == :confirm
      return render_one_click if one_click?

      redirect_to done_path, status: :see_other
    end

    private

    def skip_session_cookie
      request.session_options[:skip] = true
    end

    def assign_unsubscribe
      @notification_type = params[:notification_type].to_s
      @channel = params[:channel].to_s
      @token = params[:token].to_s
      @recipient = locate_recipient
      @type = RecordingStudioNotifications.notification_types[@notification_type]
      @outcome = outcome
    end

    def locate_recipient
      return if @notification_type.blank? || @channel.blank? || @token.blank?

      GlobalID::Locator.locate_signed(@token, for: unsubscribe_purpose)
    rescue StandardError
      nil
    end

    def unsubscribe_purpose
      RecordingStudioNotifications.unsubscribe_purpose(@notification_type, @channel)
    end

    def outcome
      return :missing unless @recipient && @type

      channel_key = @channel.to_sym
      return :required if @type.required_channels.include?(channel_key)
      return :missing unless @type.optional_channels.include?(channel_key)
      return :confirm if channel_enabled?
      return :done if params[:unsubscribed].present?

      :already
    end

    def channel_enabled?
      Preference.enabled_for?(
        recipient: @recipient,
        notification_type: @notification_type,
        channel: @channel,
        default: true
      )
    end

    def turn_channel_off!
      Preference.set!(
        recipient: @recipient,
        notification_type: @notification_type,
        channel: @channel,
        enabled: false
      )
    end

    def refusal?
      @outcome == :missing || @outcome == :required
    end

    def refusal_status
      @outcome == :missing ? :not_found : :unprocessable_entity
    end

    def one_click?
      request.raw_post == "List-Unsubscribe=One-Click" || params["List-Unsubscribe"] == "One-Click"
    end

    def render_one_click
      render plain: Copy.t("unsubscribe.one_click_body", default: "Unsubscribed."), status: :ok
    end

    def done_path
      query = request.query_parameters.merge("unsubscribed" => "1")
      "#{request.path}?#{Rack::Utils.build_query(query)}"
    end

    def unsubscribe_title
      notifications_t("unsubscribe.#{@outcome}_title")
    end

    def unsubscribe_subtitle
      notifications_t(
        "unsubscribe.#{@outcome}_subtitle",
        type: type_label,
        channel: channel_label
      )
    end

    def type_label
      @type&.label.presence || @notification_type.to_s.humanize
    end

    def channel_label
      notifications_t("channels.#{@channel}", default: @channel.to_s.humanize).downcase
    end

    def settings_href
      Engine.routes.url_helpers.settings_path
    end
  end
end
