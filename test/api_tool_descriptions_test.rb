# frozen_string_literal: true

require "test_helper"

class ApiToolDescriptionsTest < Minitest::Test
  BANNED = [
    "Preference.set!",
    "Preference.set_cadence!",
    "Preference.for_recipient",
    "authorized_root_recording_ids",
    "LIMIT",
    "OFFSET",
    "visible_notification?",
    "Notification.for_recipient",
    "mark_read!",
    "mark_unread!",
    "archive!",
    "unarchive!",
    ":manage_preferences",
    ":view_notifications",
    "Path parameter",
    "Accessible",
    "InboxScope"
  ].freeze

  NOTIFICATION_TOOLS = %w[
    notifications.show
    notifications.mark_read
    notifications.mark_unread
    notifications.archive
    notifications.unarchive
  ].freeze

  def test_inbox_and_show_match_main_copy
    api = RecordingStudioNotifications::Api::ToolDescriptions
    inbox = "List the signed-in person's notifications for this workspace, newest first. " \
            "Notifications with no workspace are included. Archived notifications are left out. " \
            "A notification sent with the inbox turned off is left out. A notice still waiting on a " \
            "grouped in-app delivery is left out. Another person's notifications are left out. " \
            "Pass page and per_page to choose the page. Use notifications.show when you need one item. " \
            "Use notifications.mark_read, notifications.mark_unread, or notifications.archive to change one. " \
            "Take id from a record in this list. Returns records and meta. Each record has " \
            "#{api::NOTIFICATION_FIELDS}. type is the string notification. read is true when read_at or " \
            "cleared_at is set. meta has page, per_page, total_count, and total_pages."
    show = "Read one notification for the signed-in person in this workspace, or one with no workspace. " \
           "Use this when you have an id from notifications.inbox and need the full item. #{api::HIDDEN} " \
           "Use notifications.mark_read, notifications.mark_unread, or notifications.archive to change it. " \
           "#{api::NOTIFICATION_SHAPE}"

    assert_equal inbox, api::INBOX
    assert_equal show, api::SHOW
    assert_equal format(
      api::SHOW_FORMAT,
      inbox: "notifications.inbox",
      read: "notifications.mark_read",
      unread: "notifications.mark_unread",
      archive: "notifications.archive"
    ), api::SHOW
  end

  def test_each_tool_description_is_plain_language
    assert_equal 8, endpoints.size

    endpoints.each do |endpoint|
      text = endpoint.fetch(:openapi).fetch(:description)
      name = endpoint.fetch(:name)

      assert_operator text.split.size, :>=, 40, name
      refute_banned(text, name)
    end
  end

  def test_each_parameter_description_explains_the_input
    endpoints.each do |endpoint|
      name = endpoint.fetch(:name)
      parameter_texts(endpoint).each do |field, text|
        label = "#{name} #{field}"

        refute_equal "Path parameter id.", text
        assert_operator text.to_s.split.size, :>=, 8, label
        refute_banned(text, label)
      end
    end

    inbox = endpoint("notifications.inbox")
    page = field_text(inbox, :page)
    per_page = field_text(inbox, :per_page)

    assert_includes page, "1"
    assert_equal inbox_page_size, RecordingStudioNotifications::Api::ToolDescriptions::PAGE_SIZE.to_s
    assert_includes per_page, inbox_page_size
    assert_equal page, openapi_parameter_text(inbox, "page")
    assert_equal per_page, openapi_parameter_text(inbox, "per_page")

    (NOTIFICATION_TOOLS + ["notifications.show"]).uniq.each do |name|
      assert_match(/\bnotifications\.inbox\b/, field_text(endpoint(name), :id), name)
    end
  end

  def test_documented_channel_and_cadence_values_match_the_registry
    update = endpoint("notifications.update_preferences")
    tool = update.fetch(:openapi).fetch(:description)
    channel = field_text(update, :channel)
    cadence = field_text(update, :cadence)

    assert_match(/\bnotifications\.preferences\b/, field_text(update, :notification_type))

    bundled_channels = RecordingStudioNotifications::Configuration.new.channels.keys
    bundled_channels.each do |key|
      assert_match(/\b#{Regexp.escape(key)}\b/, channel, key.to_s)
      assert_match(/\b#{Regexp.escape(key)}\b/, tool, key.to_s)
    end

    RecordingStudioNotifications::NotificationTypeRegistry::CADENCES.each do |value|
      assert_match(/\b#{Regexp.escape(value)}\b/, cadence, value.to_s)
      assert_match(/\b#{Regexp.escape(value)}\b/, tool, value.to_s)
    end
  end

  def test_documented_return_fields_match_the_serializers
    notification_keys.each do |key|
      (["notifications.inbox"] + NOTIFICATION_TOOLS).each do |name|
        assert_includes_field endpoint(name).fetch(:openapi).fetch(:description), key, name
      end
    end

    %w[page per_page total_count total_pages records].each do |key|
      assert_includes_field endpoint("notifications.inbox").fetch(:openapi).fetch(:description), key, "inbox meta"
    end

    preference_keys.each do |key|
      %w[notifications.preferences notifications.update_preferences].each do |name|
        assert_includes_field endpoint(name).fetch(:openapi).fetch(:description), key, name
      end
    end
  end

  private

  def inbox_page_size
    controller = File.read(
      File.expand_path("../app/controllers/recording_studio_notifications/notifications_controller.rb", __dir__)
    )
    controller[/PER_PAGE = (\d+)/, 1] || flunk("inbox page size missing")
  end

  def endpoints
    RecordingStudioNotifications::Api::ENDPOINTS
  end

  def endpoint(name)
    endpoints.find { |item| item.fetch(:name) == name } || flunk("missing #{name}")
  end

  def parameter_texts(endpoint)
    texts = {}
    contract = endpoint[:input_contract]
    contract&.fetch(:fields)&.each do |field, rules|
      texts[field.to_s] = rules[:description]
    end
    Array(endpoint.fetch(:openapi)[:parameters]).each do |parameter|
      texts[parameter.fetch(:name)] = parameter[:description]
    end
    texts
  end

  def field_text(endpoint, field)
    endpoint.fetch(:input_contract).fetch(:fields).fetch(field).fetch(:description)
  end

  def openapi_parameter_text(endpoint, name)
    endpoint.fetch(:openapi).fetch(:parameters).find { |parameter| parameter.fetch(:name) == name }.fetch(:description)
  end

  def refute_banned(text, label)
    BANNED.each do |phrase|
      refute_includes text, phrase, "#{label} mentions #{phrase}"
    end
  end

  def assert_includes_field(text, field, label)
    assert_match(/\b#{Regexp.escape(field)}\b/, text, "#{label} omits #{field}")
  end

  def notification_keys
    record = Struct.new(
      :id, :notification_type, :title, :body, :url, :inbox,
      :read_at, :archived_at, :cleared_at, :recording_id, :root_recording_id, :created_at,
      keyword_init: true
    ) do
      def read?
        false
      end

      def archived?
        false
      end
    end.new(
      id: "n",
      notification_type: "generic",
      title: "Title",
      body: "Body",
      url: "/",
      inbox: true,
      read_at: nil,
      archived_at: nil,
      cleared_at: nil,
      recording_id: nil,
      root_recording_id: nil,
      created_at: Time.now
    )

    RecordingStudioNotifications::Api::Serialize.notification(record).keys.map(&:to_s)
  end

  def preference_keys
    row = Struct.new(:id, :notification_type, :channel, :enabled, :cadence, keyword_init: true).new(
      id: "p",
      notification_type: "generic",
      channel: "in_app",
      enabled: true,
      cadence: nil
    )

    RecordingStudioNotifications::Api::Serialize.channel_preference(row).keys.map(&:to_s)
  end
end
