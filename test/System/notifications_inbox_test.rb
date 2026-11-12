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
    assert_includes index, ".rsn-inbox-card .text-\\(--surface-content-color\\)"
    assert_includes index, ".rsn-inbox-card .text-\\(--surface-muted-content-color\\)"
    assert_includes index, "color: var(--surface-content-color);"
    assert_includes index, "color: var(--surface-muted-content-color);"
    assert_includes notification, 'weight = notification.unread? ? "font-semibold" : "font-normal"'
    assert_includes notification, 'title_color = notification.unread? ? "text-(--surface-content-color)" : "text-(--surface-muted-content-color)"'
    assert_includes notification, "truncate text-sm <%= weight %> <%= title_color %>"
    assert_includes notification, "line-clamp-2 text-xs <%= weight %>"
    assert_includes notification, 'class: "text-sm #{weight} text-(--surface-muted-content-color) whitespace-nowrap"'
    refute_includes notification, "font-medium"
    refute_includes notification, "class_name:"

    assert_includes group, "unread = group.unread_count.positive?"
    assert_includes group, 'weight = unread ? "font-semibold" : "font-normal"'
    assert_includes group, 'title_color = unread ? "text-(--surface-content-color)" : "text-(--surface-muted-content-color)"'
    assert_includes group, "block truncate <%= weight %> <%= title_color %>"
    assert_includes group, "text-xs <%= weight %> text-(--surface-muted-content-color)"
    assert_includes group, 'class: "text-sm #{weight} text-(--surface-muted-content-color) whitespace-nowrap"'
    assert_includes group, "notifications/notification"

    assert_includes menu, "style: :plain"
    assert_includes menu, "divider: true"
    assert_includes menu, 'unread = n[:unread] == true || n["unread"] == true'
    assert_includes menu, 'weight = unread ? "font-semibold" : "font-normal"'
    assert_includes menu, 'title_color = unread ? "text-(--surface-content-color)" : "text-(--surface-muted-content-color)"'
    assert_includes menu, "line-clamp-2 text-xs <%= weight %>"
    assert_includes menu, 'class: "text-sm #{weight} text-(--surface-muted-content-color) whitespace-nowrap"'
    assert_includes menu, "notification_menu_leading_icon(n)"
    assert_includes menu, "FlatPack::Notification::Component.new"
    refute_includes menu, "<style"
    refute_includes menu, "rsn-notification-menu"
    refute_includes menu, "fp-red-dot"
    refute_includes menu, "fp-rollup-counter-badge"
    refute_includes menu, "flat-pack-list"
    refute_includes menu, "list-item-active-background-color"
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
