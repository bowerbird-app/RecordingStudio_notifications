# frozen_string_literal: true

require_relative "fan_out_batch"
require_relative "fan_out_payload"
require_relative "notification_authorization"

module RecordingStudioNotifications
  module Services
    class FanOut
      CHUNK_SIZE = 1_000
      Request = Struct.new(
        :notification_type, :type_definition, :title, :body, :url, :metadata, :actor, :notifiable,
        :recording, :recording_id, :root_recording_id, :idempotency_key, :idempotency_index, :inbox,
        :requested_channels, :rollup_enabled, :preference_table,
        keyword_init: true
      )

      def self.chunk_size
        CHUNK_SIZE
      end

      def self.enqueue(recipient_scope:, idempotency_key:, **attributes)
        FanOutJob.perform_later(FanOutPayload.build(recipient_scope:, idempotency_key:, **attributes))
      end

      def self.perform(attributes)
        new(attributes).call
      end

      def initialize(attributes)
        @attributes = attributes.symbolize_keys
        @recipient_scope = @attributes.fetch(:recipient_scope).to_s
        @idempotency_key = @attributes.fetch(:idempotency_key).to_s
        @notification_type = @attributes.fetch(:notification_type).to_s
        @title = @attributes[:title]
        @body = @attributes[:body]
        @url = @attributes[:url]
        @metadata = @attributes[:metadata].presence || {}
        @requested_channels = restore_channels(@attributes[:channels])
        @inbox_override = @attributes[:inbox]
        @actor = locate(@attributes[:actor_gid])
        @notifiable = locate(@attributes[:notifiable_gid])
        @recording = locate(@attributes[:recording_gid])
        @root_recording = locate(@attributes[:root_recording_gid])
      end

      def call
        check!
        each_batch { |recipients| write_batch(recipients) }
      end

      private

      def check!
        raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?
        raise ArgumentError, "title is required" if @title.to_s.blank?
        raise ArgumentError, "notification_type is not registered" unless type_definition
        raise ArgumentError, "root_recording is required" if type_definition.scope == :root && resolved_root.blank?
        raise ArgumentError, "root_recording does not match recording or notifiable" unless consistent_root?
        raise ArgumentError, "url is too long" if @url.to_s.length > 2048

        reject_hidden_required_in_app!
        validate_channels!
        UrlSafety.sanitize!(@url)
        authorize!
      end

      def validate_channels!
        unknown = candidate_channels.find { |channel| !RecordingStudioNotifications.channels.registered?(channel) }
        raise ArgumentError, "channel is not registered: #{unknown}" if unknown
        return unless type_definition.available_channels

        unavailable = candidate_channels.find { |channel| !type_definition.available_channels.include?(channel) }
        return unless unavailable

        raise ArgumentError, "channel is not available for #{@notification_type}: #{unavailable}"
      end

      def candidate_channels
        required = type_definition.required_channels
        requested = @requested_channels
        requested = type_definition.default_channels if requested.nil?
        requested = RecordingStudioNotifications.configuration.default_channels if requested.nil?
        (Array(requested).map { |channel| channel.to_s.strip.to_sym } + required).uniq
      end

      def reject_hidden_required_in_app!
        return if inbox?
        return unless type_definition.required_channels.include?(:in_app)

        raise ArgumentError, "inbox cannot be false when in_app is a required channel"
      end

      def authorize!
        action = type_definition.creation_action
        return unless action
        return if creation_allowed?(action)

        raise NotificationAuthorization::NotAuthorized, "not authorized to create #{@notification_type} notifications"
      end

      def creation_allowed?(action)
        return false unless defined?(RecordingStudioAccessible)
        return false unless RecordingStudioAccessible.respond_to?(:authorized_action?)

        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: action,
          recording: resolved_root || @recording,
          context: {
            recipient: nil,
            notification_type: @notification_type.to_sym,
            notifiable: @notifiable,
            metadata: @metadata
          }
        )
      end

      def each_batch(&)
        resolved = RecordingStudioNotifications.configuration.recipient_scopes.resolve(@recipient_scope, scope_context)
        if resolved.respond_to?(:find_in_batches)
          resolved.except(:order).find_in_batches(batch_size: self.class.chunk_size, &)
        else
          Array(resolved).each_slice(self.class.chunk_size, &)
        end
      end

      def write_batch(recipients)
        Notification.transaction do
          FanOutBatch.insert(request, recipients).inserted.each { |inserted| run_hooks(inserted) }
        end
        enqueue_deliveries(FanOutBatch.pending_immediate_ids(@idempotency_key, recipients))
      end

      def enqueue_deliveries(delivery_ids)
        return if delivery_ids.blank?

        FanOutDeliveryJob.perform_later(delivery_ids)
      end

      def run_hooks(inserted)
        hooks.run(:before_service, self.class, hook_payload(inserted))
        result = hooks.run_around(:around_service, self) do
          ActiveSupport::Notifications.instrument("notify.recording_studio_notifications", event_payload(inserted)) do
            inserted.notification
          end
        end
        hooks.run(:after_service, self.class, result)
      end

      def hook_payload(inserted)
        {
          notification_type: @notification_type,
          recipient: inserted.recipient,
          actor: @actor,
          notifiable: @notifiable,
          recording: @recording,
          root_recording: resolved_root,
          channels: inserted.channels
        }
      end

      def event_payload(inserted)
        {
          notification_type: @notification_type,
          recipient: inserted.recipient,
          channels: inserted.channels,
          root_recording_id: request.root_recording_id
        }
      end

      def request
        @request ||= Request.new(
          notification_type: @notification_type,
          type_definition: type_definition,
          title: @title.to_s,
          body: @body,
          url: @url,
          metadata: @metadata,
          actor: @actor,
          notifiable: @notifiable,
          recording: @recording,
          recording_id: stored_recording_id,
          root_recording_id: stored_root_id,
          idempotency_key: @idempotency_key,
          idempotency_index: FanOutBatch.idempotency_index_name,
          inbox: inbox?,
          requested_channels: @requested_channels,
          rollup_enabled: RecordingStudioNotifications.configuration.rollup_delivery_enabled,
          preference_table: preference_table?
        )
      end

      def scope_context
        RecipientScopeRegistry::Context.new(
          actor: @actor,
          recording: @recording,
          notifiable: @notifiable,
          root_recording: @root_recording
        )
      end

      def type_definition
        return @type_definition if defined?(@type_definition)

        @type_definition = RecordingStudioNotifications.notification_types[@notification_type]
      end

      def resolved_root
        return nil if type_definition&.scope == :global

        @resolved_root ||= RootResolver.call(
          root_recording: @root_recording,
          recording: @recording,
          recordable: @notifiable
        )
      end

      def consistent_root?
        return true if type_definition.scope == :global

        RootResolver.consistent?(
          root_recording: resolved_root,
          recording: @recording,
          recordable: @notifiable
        )
      end

      def stored_recording_id
        return nil if type_definition.scope == :global

        @recording&.id
      end

      def stored_root_id
        return nil if type_definition.scope == :global

        resolved_root&.id
      end

      def inbox?
        return @inbox_override unless @inbox_override.nil?

        type_definition.inbox != false
      end

      def preference_table?
        return @preference_table if defined?(@preference_table)

        @preference_table = defined?(RecordingStudioNotifications::Preference) &&
                            RecordingStudioNotifications::Preference.table_exists?
      end

      def restore_channels(channels)
        return nil if channels.nil?

        Array(channels).map { |channel| channel.to_s.strip.to_sym }
      end

      def locate(gid)
        return if gid.blank?

        GlobalID::Locator.locate(gid)
      end

      def hooks
        RecordingStudioNotifications.configuration.hooks
      end
    end
  end
end
