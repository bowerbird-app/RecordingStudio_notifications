# frozen_string_literal: true

module RecordingStudioNotifications
  module MenuJson
    private

    def menu_json
      visible = visible_notifications(scoped_notifications)
      limit = normalized_menu_limit
      groups = grouped_notification_sections(visible).flat_map(&:groups)
      recent_groups = groups.sort_by { |group| [group.latest_notification.created_at, group.id] }.reverse.first(limit)
      payload = recent_groups.map { |group| menu_group_payload(group) }
      unread_count = visible.count(&:unread?)

      {
        unread_count: unread_count,
        notifications: payload,
        polling_interval_seconds: RecordingStudioNotifications.configuration.polling_interval_seconds,
        menu_html: menu_component_html(unread_count, payload)
      }
    end

    def menu_component_html(unread_count, payload)
      render_to_string(
        partial: "recording_studio_notifications/notifications/menu_component",
        formats: [:html],
        locals: {
          unread_count: unread_count,
          notifications: payload,
          see_all_href: notifications_path,
          bell_label: Copy.t("menu.title", default: "Notifications"),
          empty_text: Copy.t("menu.empty", default: "No recent notifications")
        }
      )
    end

    def normalized_menu_limit
      requested_limit = params[:limit].to_i
      return 5 if requested_limit <= 0

      [requested_limit, 25].min
    end

    def menu_notification_payload(notification)
      MenuPayload.serialize(
        notification: notification,
        href: open_notification_path(notification)
      )
    end

    def menu_group_payload(group)
      return menu_notification_payload(group.latest_notification) if group.individual?

      menu_notification_payload(group.latest_notification).merge(
        title: group.notification_type_label,
        body: group.period_label,
        href: nil,
        unread: group.unread_count.positive?,
        rollup: true,
        children: group.notifications.map { |notification| menu_notification_payload(notification) }
      )
    end
  end
end
