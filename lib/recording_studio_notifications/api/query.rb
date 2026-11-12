# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    module Query
      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 100

      module_function

      def paginate(items, page:, per_page:)
        normalized_page = normalize_page(page)
        normalized_per_page = normalize_per_page(per_page)
        total_count = items.size
        offset = (normalized_page - 1) * normalized_per_page
        {
          rows: Array(items[offset, normalized_per_page]),
          meta: {
            page: normalized_page,
            per_page: normalized_per_page,
            total_count: total_count,
            total_pages: [(total_count.to_f / normalized_per_page).ceil, 1].max
          }
        }
      end

      def normalize_page(page)
        requested = page.to_i
        requested.positive? ? requested : 1
      end

      def normalize_per_page(per_page)
        requested = per_page.to_i
        requested = DEFAULT_PER_PAGE if requested <= 0
        [requested, MAX_PER_PAGE].min
      end
    end
  end
end
