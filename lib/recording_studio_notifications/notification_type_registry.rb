# frozen_string_literal: true

module RecordingStudioNotifications
  NotificationType = Struct.new(
    :key,
    :label,
    :description,
    :icon,
    :default_channels,
    :required_channels,
    :available_channels,
    :scope,
    :creation_action,
    keyword_init: true
  ) do
    def optional_channels
      Array(available_channels) - required_channels
    end
  end

  class NotificationTypeRegistry
    SCOPES = %i[global root optional_root].freeze

    def initialize
      @types = {}
      @mutex = Mutex.new
    end

    def register(key, label:, description: nil, icon: nil, default_channels: nil, required_channels: [],
                 available_channels: nil, scope: :optional_root, creation_action: nil)
      normalized_key = normalize_key!(key)
      normalized_icon = normalize_icon(icon)
      normalized_required = normalize_channels(required_channels)
      default_channels_provided = !default_channels.nil?
      normalized_default = default_channels_provided ? normalize_channels(default_channels) : nil
      available_source = available_channels.nil? ? default_available_channels(normalized_default, normalized_required) : available_channels
      normalized_available = available_source.nil? ? nil : normalize_channels(available_source)
      normalized_scope = normalize_scope!(scope)

      normalized_required.each do |channel|
        unless normalized_available.include?(channel)
          raise ArgumentError, "required channel #{channel.inspect} must be available"
        end
      end

      metadata = NotificationType.new(
        key: normalized_key,
        label: label.to_s,
        description: description&.to_s,
        icon: normalized_icon,
        default_channels: normalized_default,
        required_channels: normalized_required,
        available_channels: normalized_available,
        scope: normalized_scope,
        creation_action: creation_action&.to_sym
      ).freeze

      @mutex.synchronize { @types[normalized_key] = metadata }
      metadata
    end

    def fetch(key)
      @mutex.synchronize { @types.fetch(normalize_key!(key)) }
    end

    def [](key)
      @mutex.synchronize { @types[normalize_key!(key)] }
    end

    def registered?(key)
      @mutex.synchronize { @types.key?(normalize_key!(key)) }
    rescue ArgumentError
      false
    end

    def keys
      @mutex.synchronize { @types.keys.sort_by(&:to_s) }
    end

    def values
      @mutex.synchronize { @types.values.sort_by { |type| type.key.to_s } }
    end

    def clear!
      @mutex.synchronize { @types.clear }
    end

    private

    def default_available_channels(default_channels, required_channels)
      return nil if default_channels.nil? && required_channels.empty?

      Array(default_channels) + required_channels
    end

    def normalize_channels(channels)
      Array(channels).map { |channel| normalize_key!(channel) }.uniq
    end

    def normalize_icon(icon)
      icon.to_s.strip.presence&.to_sym || :bell
    end

    def normalize_scope!(scope)
      normalized = normalize_key!(scope)
      return normalized if SCOPES.include?(normalized)

      raise ArgumentError, "scope must be one of: #{SCOPES.join(', ')}"
    end

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "notification type is required" if normalized.blank?

      normalized.to_sym
    end
  end
end
