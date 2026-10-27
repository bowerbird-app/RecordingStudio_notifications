# frozen_string_literal: true

require "test_helper"

class NotificationsInboxTest < Minitest::Test
  def test_unread_titles_are_semibold_and_read_titles_are_regular
    notification = File.read(view("notifications/_notification.html.erb"))
    group = File.read(view("notifications/_group.html.erb"))
    index = File.read(view("notifications/index.html.erb"))
    menu = File.read(view("notifications/_menu_component.html.erb"))
    menu_helper = File.read(helper("menu_helper.rb"))

    assert_includes index, "notifications/page"
    assert_includes notification, 'notification.unread? ? "font-semibold" : "font-normal"'
    assert_includes notification, "truncate text-sm"
    assert_includes notification, "line-clamp-2 text-xs font-normal"
    assert_includes notification, "font-normal text-(--surface-muted-content-color) whitespace-nowrap"
    refute_includes notification, "font-medium"
    refute_includes notification, "font-semibold text-xs"

    assert_includes group, 'group.unread_count.positive? ? "font-semibold" : "font-normal"'
    assert_includes group, "text-xs font-normal text-(--surface-muted-content-color)"
    assert_includes group, "text-sm font-normal text-(--surface-muted-content-color) whitespace-nowrap"
    assert_includes group, "notifications/notification"

    refute_includes menu, "font-semibold"
    refute_includes menu, "font-normal"
    assert_includes menu, "FlatPack::Notification::Component.new"
    refute_includes menu_helper, "font-semibold"
    refute_includes menu_helper, "font-normal"
  end

  private

  def view(path)
    File.expand_path("../../app/views/recording_studio_notifications/#{path}", __dir__)
  end

  def helper(path)
    File.expand_path("../../app/helpers/recording_studio_notifications/#{path}", __dir__)
  end
end
