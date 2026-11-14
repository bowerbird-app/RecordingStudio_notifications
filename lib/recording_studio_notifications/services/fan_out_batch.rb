# frozen_string_literal: true

require_relative "cadence_period"
require_relative "fan_out_channels"

module RecordingStudioNotifications
  module Services
    # One chunk of fan-out inserts. Call inside a transaction.
    class FanOutBatch
      Plan = Struct.new(:recipient, :channels, :cadence, :time_zone, keyword_init: true) do
        def deferred?
          cadence != :individual
        end
      end
      Inserted = Struct.new(:notification, :recipient, :channels, keyword_init: true)
      Outcome = Struct.new(:inserted, :immediate_delivery_ids, keyword_init: true)
      IDEMPOTENCY_COLUMNS = %w[recipient_type recipient_id idempotency_key].freeze

      def self.insert(request, recipients)
        new(request, recipients).insert
      end

      def initialize(request, recipients)
        @request = request
        @recipients = recipients.uniq { |recipient| recipient_key(recipient) }
      end

      def insert
        return empty_outcome if @recipients.empty?

        timestamp = Time.current
        plans = build_plans(load_preferences)
        return empty_outcome if plans.empty?

        inserted_ids = insert_notifications(notification_rows(plans, timestamp))
        delivery_result = insert_deliveries(delivery_rows(plans, inserted_ids, timestamp))
        notifications = load_notifications(inserted_ids.values)
        Outcome.new(
          inserted: inserted_records(plans, inserted_ids, notifications),
          immediate_delivery_ids: immediate_ids(plans, inserted_ids, delivery_result)
        )
      end

      private

      def empty_outcome
        Outcome.new(inserted: [], immediate_delivery_ids: [])
      end

      def load_preferences
        return {} unless @request.preference_table

        Preference.where(
          notification_type: @request.notification_type,
          recipient_type: @recipients.map { |recipient| recipient.class.base_class.name }.uniq,
          recipient_id: @recipients.map(&:id)
        ).each_with_object({}) do |preference, grouped|
          bucket = grouped[preference_key(preference)] ||= { channels: {}, cadence: nil }
          assign_preference(bucket, preference)
        end
      end

      def assign_preference(bucket, preference)
        if preference.channel.nil?
          bucket[:cadence] = preference.cadence
        else
          bucket[:channels][preference.channel.to_sym] = preference.enabled
        end
      end

      def build_plans(preferences)
        @recipients.filter_map do |recipient|
          preference = preferences[recipient_key(recipient)] || { channels: {}, cadence: nil }
          channels = channels_for(recipient, preference)
          next if channels.empty?

          plan = Plan.new(
            recipient: recipient,
            channels: channels,
            cadence: cadence_for(preference),
            time_zone: time_zone_for(recipient)
          )
          ensure_rollup!(plan)
          plan
        end
      end

      def channels_for(recipient, preference)
        FanOutChannels.new(
          type: @request.type_definition,
          requested_channels: @request.requested_channels,
          inbox: @request.inbox,
          preference_channels: preference[:channels],
          recipient: recipient
        ).keys
      end

      def cadence_for(preference)
        type = @request.type_definition
        return :individual unless @request.rollup_enabled
        return type.required_cadence if type.required_cadence
        return type.default_cadence if preference[:cadence].blank?

        preference[:cadence].to_sym
      end

      def time_zone_for(recipient)
        recipient.try(:time_zone).presence || Time.zone || "UTC"
      end

      def ensure_rollup!(plan)
        return unless plan.deferred?

        unsupported = plan.channels.find { |channel| !rollup_capable?(channel) }
        return unless unsupported

        raise ArgumentError, "channel does not support grouped delivery: #{unsupported}"
      end

      def rollup_capable?(channel)
        RecordingStudioNotifications.channels.fetch(channel).respond_to?(:deliver_rollup)
      end

      def notification_rows(plans, timestamp)
        plans.map { |plan| notification_row(plan.recipient, timestamp) }
      end

      def notification_row(recipient, timestamp)
        {
          notification_type: @request.notification_type,
          recipient_type: recipient.class.base_class.name,
          recipient_id: recipient.id,
          actor_type: polymorphic_name(@request.actor),
          actor_id: @request.actor&.id,
          notifiable_type: polymorphic_name(@request.notifiable),
          notifiable_id: @request.notifiable&.id,
          recording_id: @request.recording_id,
          root_recording_id: @request.root_recording_id,
          title: @request.title,
          body: @request.body,
          url: @request.url,
          metadata: @request.metadata.deep_dup,
          idempotency_key: @request.idempotency_key,
          inbox: @request.inbox,
          created_at: timestamp,
          updated_at: timestamp
        }
      end

      def insert_notifications(rows)
        Notification.insert_all(
          rows,
          unique_by: @request.idempotency_index,
          returning: %w[id recipient_type recipient_id]
        ).each_with_object({}) do |row, ids|
          ids[[row["recipient_type"], row["recipient_id"].to_s]] = row["id"]
        end
      end

      def delivery_rows(plans, inserted_ids, timestamp)
        plans.flat_map do |plan|
          notification_id = inserted_ids[recipient_key(plan.recipient)]
          next [] unless notification_id

          plan.channels.map { |channel| delivery_row(notification_id, plan, channel, timestamp) }
        end
      end

      def delivery_row(notification_id, plan, channel, timestamp)
        {
          notification_id: notification_id,
          channel: channel.to_s,
          status: "pending",
          metadata: rollup_metadata(plan, channel, timestamp),
          created_at: timestamp,
          updated_at: timestamp
        }
      end

      def rollup_metadata(plan, channel, timestamp)
        return {} unless plan.deferred?

        period = CadencePeriod.for(timestamp: timestamp, cadence: plan.cadence, time_zone: plan.time_zone)
        starts_at = period.starts_at.utc.iso8601
        {
          "rollup" => true,
          "rollup_key" => rollup_key(plan, channel, starts_at),
          "cadence" => plan.cadence.to_s,
          "period_starts_at" => starts_at,
          "period_ends_at" => period.ends_at.utc.iso8601
        }
      end

      def rollup_key(plan, channel, starts_at)
        [
          "#{plan.recipient.class.name}:#{plan.recipient.id}",
          @request.notification_type,
          channel,
          plan.cadence,
          starts_at
        ].join("/")
      end

      def insert_deliveries(rows)
        return [] if rows.empty?

        Delivery.insert_all(rows, returning: %w[id notification_id]).to_a
      end

      def load_notifications(ids)
        return {} if ids.empty?

        Notification.where(id: ids).index_by { |notification| notification.id.to_s }
      end

      def inserted_records(plans, inserted_ids, notifications)
        plans.filter_map do |plan|
          id = inserted_ids[recipient_key(plan.recipient)]
          next unless id

          Inserted.new(
            notification: notifications.fetch(id.to_s),
            recipient: plan.recipient,
            channels: plan.channels
          )
        end
      end

      def immediate_ids(plans, inserted_ids, delivery_result)
        immediate_notification_ids = plans.filter_map do |plan|
          next if plan.deferred?

          inserted_ids[recipient_key(plan.recipient)]&.to_s
        end
        delivery_result.filter_map do |row|
          row["id"] if immediate_notification_ids.include?(row["notification_id"].to_s)
        end
      end

      def polymorphic_name(record)
        return if record.nil?

        record.class.base_class.name
      end

      def recipient_key(recipient)
        [recipient.class.base_class.name, recipient.id.to_s]
      end

      def preference_key(preference)
        [preference.recipient_type, preference.recipient_id.to_s]
      end

      class << self
        def idempotency_index_name
          index = Notification.connection.indexes(Notification.table_name).find do |candidate|
            candidate.unique &&
              candidate.columns.map(&:to_s) == IDEMPOTENCY_COLUMNS &&
              candidate.where.present?
          end
          raise ArgumentError, "notification idempotency index is missing" unless index

          index.name
        end
      end
    end
  end
end
