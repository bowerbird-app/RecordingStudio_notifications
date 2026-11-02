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

  def test_control_characters_and_backslashes_are_rejected
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\nb")
    refute RecordingStudioNotifications::UrlSafety.safe?("/\\evil")
    refute RecordingStudioNotifications::UrlSafety.safe?("\x00")
    refute RecordingStudioNotifications::UrlSafety.safe?("https://example.com/a\\b", allowed_hosts: ["example.com"])
    refute RecordingStudioNotifications::UrlSafety.safe?("/path\x7F")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\tb")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\rb")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\u0090b")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\u2028b")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a\u2029b")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a%0Ab")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a%00b")
    refute RecordingStudioNotifications::UrlSafety.safe?("/a%0ab")
    refute RecordingStudioNotifications::UrlSafety.safe?("https://example.com/a%0A", allowed_hosts: ["example.com"])
    refute RecordingStudioNotifications::UrlSafety.safe?("https://example.com/path?next=%00", allowed_hosts: ["example.com"])

    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications::UrlSafety.sanitize!("/\\evil")
    end
    assert_equal "unsafe notification URL", error.message
  end

  def test_blank_urls_and_existing_safe_urls_stay_safe
    assert RecordingStudioNotifications::UrlSafety.safe?("\n")
    assert RecordingStudioNotifications::UrlSafety.safe?(" ")
    assert RecordingStudioNotifications::UrlSafety.safe?("/recordings/123")
    assert RecordingStudioNotifications::UrlSafety.safe?("https://example.com/a%5C", allowed_hosts: ["example.com"])
  end

  def test_absolute_urls_require_allowed_host
    assert RecordingStudioNotifications::UrlSafety.safe?("https://example.com/path", allowed_hosts: ["example.com"])
    refute RecordingStudioNotifications::UrlSafety.safe?("https://evil.example/path", allowed_hosts: ["example.com"])
  end
end
