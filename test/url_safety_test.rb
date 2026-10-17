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

  def test_sanitize_allows_blank_and_relative_urls_and_rejects_javascript
    assert_nil RecordingStudioNotifications::UrlSafety.sanitize!(nil)
    assert_equal "/recordings/123", RecordingStudioNotifications::UrlSafety.sanitize!("/recordings/123")

    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications::UrlSafety.sanitize!("javascript:alert(1)")
    end
    assert_equal "unsafe notification URL", error.message
  end

  def test_invalid_uri_is_unsafe
    refute RecordingStudioNotifications::UrlSafety.safe?("http://[")
  end

  def test_absolute_urls_require_allowed_host
    assert RecordingStudioNotifications::UrlSafety.safe?("https://example.com/path", allowed_hosts: ["example.com"])
    refute RecordingStudioNotifications::UrlSafety.safe?("https://evil.example/path", allowed_hosts: ["example.com"])
  end
end
