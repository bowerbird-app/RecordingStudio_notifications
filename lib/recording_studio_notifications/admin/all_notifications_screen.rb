# frozen_string_literal: true

module RecordingStudioNotifications
  module Admin
    class AllNotificationsScreen < RecordingStudioAdmin::Screen
      key "recording_studio_notifications_all_notifications"
      icon :bell
      title "All notifications"
      subtitle "Root-scoped and global notification overview"

      query do |_context|
        RecordingStudioNotifications::Notification
          .includes(:recipient, :actor, :deliveries)
          .newest_first
      end

      summary do
        label "Notifications"
      end

      table do
        filter :search, apply: lambda { |relation, value, _context|
          if value.present?
            q = "%#{value.to_s.downcase}%"
            relation.where(
              "LOWER(notification_type) LIKE :q OR LOWER(title) LIKE :q OR LOWER(COALESCE(actor_type, '')) LIKE :q OR LOWER(recipient_type) LIKE :q",
              q: q
            )
          else
            relation
          end
        }

        column :notification_type, title: "Type"
        column :scope,
               title: "Scope",
               sortable: false,
               value: ->(row, _context) { row.root_recording_id.present? ? "Root" : "Global" }
        column :title, title: "Title"
        column :recipient,
               title: "Recipient",
               sortable: false,
               value: ->(row, _context) { "#{row.recipient_type} ##{row.recipient_id}" }
        column :actor,
               title: "Actor",
               sortable: false,
               value: ->(row, _context) { row.actor_type.presence || "-" }
        column :status,
               title: "Status",
               sortable: false,
               value: ->(row, _context) { row.read? ? "Read" : "Unread" }
        column :created_at, title: "Created"

        default_sort :created_at, direction: :desc
        paginate per_page: 50
      end

    end
  end
end