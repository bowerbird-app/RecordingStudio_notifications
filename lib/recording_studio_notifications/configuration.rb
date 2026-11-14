# frozen_string_literal: true

require_relative "hooks"
require_relative "notification_type_registry"
require_relative "channel_registry"
require_relative "recipient_scope_registry"

module RecordingStudioNotifications
  class Configuration
    INBOX_SCOPES = %w[all current_root].freeze

    attr_accessor :actor_resolver, :current_root_resolver, :allowed_url_hosts, :default_channels,
                  :deliver_later, :queue_name, :raise_on_delivery_error, :polling_interval_seconds,
                  :rollup_reservation_timeout, :rollup_delivery_enabled, :unsubscribe_expires_in
    attr_reader :hooks, :notification_types, :channels, :layout, :default_inbox_scope, :recipient_scopes

    def initialize
      @actor_resolver = -> { Current.actor if defined?(Current) && Current.respond_to?(:actor) }
      @current_root_resolver = ->(controller:) { resolve_controller_root(controller) }
      @allowed_url_hosts = []
      @default_channels = [:in_app]
      @deliver_later = true
      @queue_name = :default
      @raise_on_delivery_error = false
      @polling_interval_seconds = 60
      @rollup_reservation_timeout = 15.minutes
      @rollup_delivery_enabled = false
      @unsubscribe_expires_in = 1.year
      @default_inbox_scope = "current_root"
      @layout = nil
      @hooks = Hooks.new
      @notification_types = NotificationTypeRegistry.new
      @channels = ChannelRegistry.new
      @recipient_scopes = RecipientScopeRegistry.new
      channels.register(:in_app, Channels::InAppAdapter.new)
      notification_types.register(
        :generic,
        label: "Generic notification",
        category: :system,
        description: "Default notification type for host applications.",
        default_channels: default_channels,
        available_channels: default_channels,
        scope: :optional_root
      )
    end

    def layout=(value)
      @layout = RecordingStudio::Layout.accept(value)
    end

    def default_inbox_scope=(value)
      normalized = value.to_s
      raise ArgumentError, "default_inbox_scope must be one of: all, current_root" unless INBOX_SCOPES.include?(normalized)

      @default_inbox_scope = normalized
    end

    def inbox_scope_for(requested)
      candidate = requested.to_s
      return candidate if INBOX_SCOPES.include?(candidate)

      default_inbox_scope
    end

    def to_h
      {
        allowed_url_hosts: allowed_url_hosts,
        default_channels: default_channels,
        deliver_later: deliver_later,
        queue_name: queue_name,
        polling_interval_seconds: polling_interval_seconds,
        rollup_reservation_timeout: rollup_reservation_timeout,
        rollup_delivery_enabled: rollup_delivery_enabled,
        unsubscribe_expires_in: unsubscribe_expires_in,
        default_inbox_scope: default_inbox_scope,
        raise_on_delivery_error: raise_on_delivery_error,
        notification_types: notification_types.keys,
        channels: channels.keys,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end

    def resolve_actor
      actor_resolver&.call
    end

    def resolve_current_root(controller:)
      current_root_resolver&.call(controller: controller)
    end

    private

    def resolve_controller_root(controller)
      return unless controller

      %i[current_root_recording current_recording root_recording].each do |method_name|
        return controller.send(method_name) if controller.respond_to?(method_name, true)
      end

      nil
    end
  end
end
