# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    module Query
      module_function

      def paginate(items, page:, per_page:)
        page = page.to_i
        page = 1 unless page.positive?
        per_page = normalize_per_page(per_page)
        total_count = items.size
        offset = (page - 1) * per_page
        {
          rows: Array(items[offset, per_page]),
          meta: {
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: [(total_count.to_f / per_page).ceil, 1].max
          }
        }
      end

      def normalize_per_page(per_page)
        cap = ::RecordingStudioNotifications::NotificationsController::PER_PAGE
        requested = per_page.to_i
        requested = cap if requested <= 0
        [requested, cap].min
      end
    end
  end
end
