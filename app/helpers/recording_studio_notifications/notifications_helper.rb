# frozen_string_literal: true

module RecordingStudioNotifications
  module NotificationsHelper
    def notification_icon_for(notification)
      key = notification.respond_to?(:notification_type) ? notification.notification_type : nil
      notification_type_icon_for(key)
    end

    def notification_type_icon_for(key)
      return :bell if key.blank?

      definition = RecordingStudioNotifications.notification_types[key]
      definition&.icon || :bell
    end

    def notification_leading_icon(notification)
      notification_type_leading_icon(
        notification.respond_to?(:notification_type) ? notification.notification_type : nil,
        unread: notification.respond_to?(:unread?) && notification.unread?
      )
    end

    def notification_group_leading_icon(group)
      unread_count = group.unread_count
      return notification_type_leading_icon(group.notification_type) unless unread_count.positive?

      content_tag(:span, class: "relative inline-flex shrink-0") do
        safe_join([
          notification_type_leading_icon(group.notification_type),
          content_tag(
            :span,
            notification_group_badge_text(unread_count),
            class: "absolute -right-2 -top-2 inline-flex h-4 min-w-4 shrink-0 items-center justify-center rounded-full bg-red-600 px-1 text-[10px] font-semibold leading-none text-white",
            aria: { label: "#{unread_count} unread notifications" }
          )
        ])
      end
    end

    def notification_group_dom_id(group)
      "#{group.id}-container"
    end

    def notification_group_items_dom_id(group)
      "#{group.id}-notifications"
    end

    def notification_group_next_page_dom_id(group, page)
      "#{group.id}-next-page-#{page}"
    end

    def group_notifications_per_page
      NotificationsController::GROUP_NOTIFICATIONS_PER_PAGE
    end

    def notification_type_leading_icon(notification_type, unread: false, size: :md)
      icon_classes = ["text-[var(--surface-muted-content-color)]"]
      icon_classes << "fp-red-dot" if unread

      render FlatPack::Shared::IconComponent.new(
        name: notification_type_icon_for(notification_type),
        size: size,
        class: icon_classes.join(" ")
      )
    end

    def notification_group_badge_text(count)
      count > 9 ? "9+" : count.to_s
    end
  end
end
