# frozen_string_literal: true

require "test_helper"

class UrlSafetyTest < Minitest::Test
  def test_blank_and_relative_urls_are_safe
    assert RecordingStudioNotifications::UrlSafety.safe?(nil)
    assert RecordingStudioNotifications::UrlSafety.safe?("/recordings/123")
  end

  def test_protocol_relative_and_javascript_urls_are_rejected
    refute RecordingStudioNotifications::UrlSafety.safe?("//evil.example/path")
    refute RecordingStudioNotifications::UrlSafety.safe?("javascript:alert(1)")
  end

  def test_absolute_urls_require_allowed_host
    assert RecordingStudioNotifications::UrlSafety.safe?("https://example.com/path", allowed_hosts: ["example.com"])
    refute RecordingStudioNotifications::UrlSafety.safe?("https://evil.example/path", allowed_hosts: ["example.com"])
  end
end
