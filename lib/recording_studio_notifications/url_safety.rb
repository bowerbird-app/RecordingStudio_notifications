# frozen_string_literal: true

require "uri"

module RecordingStudioNotifications
  module UrlSafety
    module_function

    def safe?(url, allowed_hosts: RecordingStudioNotifications.configuration.allowed_url_hosts)
      return true if url.blank?

      value = url.to_s
      return false if value.match?(/[\\\x00-\x1F\x7F]/)

      uri = URI.parse(value)
      return relative_path_safe?(value) if uri.relative?
      return false unless %w[http https].include?(uri.scheme)

      Array(allowed_hosts).map(&:to_s).include?(uri.host.to_s)
    rescue URI::InvalidURIError
      false
    end

    def sanitize!(url, allowed_hosts: RecordingStudioNotifications.configuration.allowed_url_hosts)
      return if url.blank?
      return url if safe?(url, allowed_hosts: allowed_hosts)

      raise ArgumentError, "unsafe notification URL"
    end

    def relative_path_safe?(url)
      url.start_with?("/") && !url.start_with?("//") && !url.match?(/\A[a-z][a-z0-9+\-.]*:/i)
    end
  end
end
