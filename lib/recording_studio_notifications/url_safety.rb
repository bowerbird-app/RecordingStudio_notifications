# frozen_string_literal: true

require "cgi"
require "uri"

module RecordingStudioNotifications
  module UrlSafety
    UNSAFE_CHARACTERS = /[\\\x00-\x1F\x7F\u0080-\u009F\u2028\u2029]/
    DECODED_CONTROL_CHARACTERS = /[\x00-\x1F\x7F\u0080-\u009F\u2028\u2029]/
    private_constant :UNSAFE_CHARACTERS, :DECODED_CONTROL_CHARACTERS

    module_function

    def safe?(url, allowed_hosts: RecordingStudioNotifications.configuration.allowed_url_hosts)
      return true if url.blank?

      value = url.to_s
      return false if value.match?(UNSAFE_CHARACTERS)

      uri = URI.parse(value)
      return false if decoded_control_character?(uri)
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

    def decoded_control_character?(uri)
      [uri.path, uri.query, uri.fragment].compact.any? do |part|
        decoded = CGI.unescape(part).b
        next true if decoded.match?(/[\x00-\x1F\x7F]/n)

        utf8 = decoded.dup.force_encoding(Encoding::UTF_8)
        utf8.valid_encoding? && utf8.match?(DECODED_CONTROL_CHARACTERS)
      end
    end
    private_class_method :decoded_control_character?
  end
end
