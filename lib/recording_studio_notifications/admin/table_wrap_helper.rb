# frozen_string_literal: true

module RecordingStudioNotifications
  module Admin
    module ViewPathPrepend
      extend ActiveSupport::Concern

      included do
        prepend_before_action :prepend_recording_studio_notifications_admin_views
      end

      private

      def prepend_recording_studio_notifications_admin_views
        prepend_view_path(RecordingStudioNotifications::Engine.root.join("app/views"))
      end
    end

    module TableWrapHelper
      SCREEN_KEY = "recording_studio_notifications_all_notifications"

      def wrap_recording_studio_notifications_admin_table(screen, &)
        table_html = capture(&)
        return table_html unless notifications_admin_table?(screen)

        render(FlatPack::Grid::Component.new(cols: 2, align: :start)) do
          render(FlatPack::Card::Component.new(style: :outlined)) do |card|
            card.body { table_html }
          end
        end
      end

      def notifications_admin_table?(screen)
        screen&.key.to_s == SCREEN_KEY
      end
    end
  end
end
