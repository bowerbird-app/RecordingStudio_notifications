# frozen_string_literal: true

module RecordingStudioNotifications
  NotificationType = Struct.new(
    :key,
    :label,
    :category,
    :description,
    :icon,
    :default_channels,
    :required_channels,
    :available_channels,
    :allowed_cadences,
    :default_cadence,
    :required_cadence,
    :scope,
    :creation_action,
    :visible_to,
    keyword_init: true
  ) do
    def optional_channels
      Array(available_channels) - required_channels
    end

    def visible_to?(recipient)
      return true if visible_to.nil?

      visible_to.call(recipient)
    end
  end

  class NotificationTypeRegistry
    CADENCES = %i[individual daily every_other_day weekly biweekly monthly].freeze
    SCOPES = %i[global root optional_root].freeze

    def initialize
      @types = {}
      @mutex = Mutex.new
    end

    def register(key, label:, **options)
      metadata = build_notification_type(key, label, parse_register_options!(options))
      @mutex.synchronize { @types[metadata.key] = metadata }
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

    def parse_register_options!(options)
      parsed = {
        description: options.delete(:description),
        icon: options.delete(:icon),
        default_channels: options.delete(:default_channels),
        required_channels: options.delete(:required_channels) { [] },
        available_channels: options.delete(:available_channels),
        scope: options.delete(:scope) { :optional_root },
        category: options.delete(:category) { :general },
        creation_action: options.delete(:creation_action),
        allowed_cadences: options.delete(:allowed_cadences) { [:individual] },
        default_cadence: options.delete(:default_cadence) { :individual },
        required_cadence: options.delete(:required_cadence),
        visible_to: options.delete(:visible_to)
      }
      raise ArgumentError, "unknown register option: #{options.keys.join(', ')}" if options.any?

      parsed
    end

    def build_notification_type(key, label, parsed)
      normalized_key = normalize_key!(key)
      normalized_required = normalize_channels(parsed[:required_channels])
      default_channels_provided = !parsed[:default_channels].nil?
      normalized_default = default_channels_provided ? normalize_channels(parsed[:default_channels]) : nil
      available_source = if parsed[:available_channels].nil?
                           default_available_channels(normalized_default, normalized_required)
                         else
                           parsed[:available_channels]
                         end
      normalized_available = available_source.nil? ? nil : normalize_channels(available_source)
      normalized_allowed_cadences = normalize_cadences!(parsed[:allowed_cadences])
      normalized_default_cadence = normalize_cadence!(parsed[:default_cadence])
      normalized_required_cadence = parsed[:required_cadence].nil? ? nil : normalize_cadence!(parsed[:required_cadence])
      validate_cadences!(normalized_allowed_cadences, normalized_default_cadence, normalized_required_cadence)
      validate_required_channels!(normalized_required, normalized_available)

      NotificationType.new(
        key: normalized_key,
        label: label.to_s,
        category: normalize_category(parsed[:category]),
        description: parsed[:description]&.to_s,
        icon: normalize_icon(parsed[:icon]),
        default_channels: normalized_default,
        required_channels: normalized_required,
        available_channels: normalized_available,
        allowed_cadences: normalized_allowed_cadences,
        default_cadence: normalized_default_cadence,
        required_cadence: normalized_required_cadence,
        scope: normalize_scope!(parsed[:scope]),
        creation_action: parsed[:creation_action]&.to_sym,
        visible_to: normalize_visible_to!(parsed[:visible_to])
      ).freeze
    end

    def validate_cadences!(allowed_cadences, default_cadence, required_cadence)
      raise ArgumentError, "default cadence #{default_cadence.inspect} must be allowed" unless allowed_cadences.include?(default_cadence)

      return unless required_cadence
      return if allowed_cadences.include?(required_cadence)

      raise ArgumentError, "required cadence #{required_cadence.inspect} must be allowed"
    end

    def validate_required_channels!(required_channels, available_channels)
      required_channels.each do |channel|
        raise ArgumentError, "required channel #{channel.inspect} must be available" unless available_channels.include?(channel)
      end
    end

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

    def normalize_category(category)
      normalize_key!(category || :general)
    end

    def normalize_scope!(scope)
      normalized = normalize_key!(scope)
      return normalized if SCOPES.include?(normalized)

      raise ArgumentError, "scope must be one of: #{SCOPES.join(', ')}"
    end

    def normalize_cadences!(cadences)
      normalized = Array(cadences).map { |cadence| normalize_cadence!(cadence) }.uniq
      raise ArgumentError, "allowed cadences cannot be empty" if normalized.empty?

      normalized
    end

    def normalize_cadence!(cadence)
      normalized = normalize_key!(cadence)
      return normalized if CADENCES.include?(normalized)

      raise ArgumentError, "cadence must be one of: #{CADENCES.join(', ')}"
    end

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "notification type is required" if normalized.blank?

      normalized.to_sym
    end

    def normalize_visible_to!(visible_to)
      return nil if visible_to.nil?
      return visible_to if visible_to.respond_to?(:call)

      raise ArgumentError, "visible_to must be a proc"
    end
  end
end
