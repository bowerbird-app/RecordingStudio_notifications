# frozen_string_literal: true

module RecordingStudioNotifications
  module Admin
    class AllNotificationsScreen < RecordingStudioAdmin::Screen
      key "recording_studio_notifications_all_notifications"
      icon :bell
      title { Copy.t("admin.all_notifications.title") }
      subtitle { Copy.t("admin.all_notifications.subtitle") }

      query do |_context|
        RecordingStudioNotifications::Notification
          .includes(:recipient, :actor, :deliveries)
          .newest_first
      end

      summary do
        label ->(_context) { Copy.t("admin.all_notifications.summary") }
      end

      table do
        filter :search, apply: lambda { |relation, value, context|
          AllNotificationsScreen.filter_search(relation, value, context)
        }

        # Column header titles stay literal English: the Admin DSL stores them as
        # strings at class load, before I18n is ready. Keys for the same English
        # live in en.yml for hosts that override via a custom screen.
        column :notification_type, title: "Type"
        column :scope,
               title: "Scope",
               sortable: false,
               value: ->(row, _context) { AllNotificationsScreen.scope_label_for(row) }
        column :title, title: "Title"
        column :recipient,
               title: "Recipient",
               sortable: false,
               value: ->(row, _context) { "#{row.recipient_type} ##{row.recipient_id}" }
        column :actor,
               title: "Actor",
               sortable: false,
               value: ->(row, _context) { AllNotificationsScreen.actor_label_for(row) }
        column :status,
               title: "Status",
               sortable: false,
               value: ->(row, _context) { AllNotificationsScreen.status_label_for(row) }
        column :created_at, title: "Created"

        default_sort :created_at, direction: :desc
        paginate per_page: 50
      end

      class << self
        def filter_search(relation, value, _context)
          return relation if value.blank?

          q = "%#{value.to_s.downcase}%"
          relation.where(
            "LOWER(notification_type) LIKE :q OR LOWER(title) LIKE :q OR LOWER(COALESCE(actor_type, '')) LIKE :q OR LOWER(recipient_type) LIKE :q",
            q: q
          )
        end

        def scope_label_for(row)
          if row.root_recording_id.present?
            Copy.t("admin.all_notifications.scope.root")
          else
            Copy.t("admin.all_notifications.scope.global")
          end
        end

        def actor_label_for(row)
          row.actor_type.presence || Copy.t("admin.all_notifications.actor.none")
        end

        def status_label_for(row)
          if row.read?
            Copy.t("admin.all_notifications.status.read")
          else
            Copy.t("admin.all_notifications.status.unread")
          end
        end
      end
    end
  end
end
