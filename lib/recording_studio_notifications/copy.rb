# frozen_string_literal: true

module RecordingStudioNotifications
  module Copy
    PREFIX = "recording_studio.notifications"
    UNSET = Object.new.freeze

    module_function

    def t(key, **)
      I18n.t("#{PREFIX}.#{key}", **)
    end

    def l(object, **)
      I18n.l(object, **)
    end

    def provided?(value)
      !value.equal?(UNSET)
    end

    def value(override, key, **)
      provided?(override) ? override : t(key, **)
    end

    def compact_day(date)
      l(date, format: "%b %-d")
    end

    def compact_month(date)
      l(date, format: "%b %Y")
    end
  end
end
