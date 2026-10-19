# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    FailedDeliveriesWidget = RecordingStudioAdmin::Widget.new(
      FailedDeliveriesChart::WIDGET_KEY,
      blast_radius: :site
    ) do
      type :chart
      title { Copy.t("admin.failed_deliveries.title", default: "Failed deliveries") }
      info { Copy.t("admin.failed_deliveries.info", default: "Sends that are still failed. A later success drops off.") }
      change_good_when :down
      chart_type :line
      series { |context| FailedDeliveriesChart.series(context) }
      link_label { Copy.t("admin.failed_deliveries.open", default: "See the chart") }
      link_to { |context| context.admin_screen_path(FailedDeliveriesChart::SCREEN_KEY) }
    end
  end
end
