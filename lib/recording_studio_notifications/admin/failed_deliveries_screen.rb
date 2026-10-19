# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    class FailedDeliveriesScreen < RecordingStudioAdmin::Screen
      key FailedDeliveriesChart::SCREEN_KEY
      icon :bell
      blast_radius :site
      title { Copy.t("admin.failed_deliveries.title", default: "Failed deliveries") }
      subtitle { Copy.t("admin.failed_deliveries.subtitle", default: "By channel, over time") }

      summary do
        label ->(_context) { Copy.t("admin.failed_deliveries.summary", default: "Failed") }
        value ->(context) { FailedDeliveriesChart.total(context) }
        change_good_when :down
      end

      chart do
        title { Copy.t("admin.failed_deliveries.title", default: "Failed deliveries") }
        type :line
        series { |context| FailedDeliveriesChart.series(context) }
      end

      widget FailedDeliveriesChart::WIDGET_KEY
    end
  end
end
