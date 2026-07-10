# frozen_string_literal: true

require "test_helper"
require "recording_studio_notifications/services/digest_summary_presenter"

class DigestSummaryPresenterTest < Minitest::Test
  Digest = Struct.new(:notification_type, :cadence, :period_starts_at, :period_ends_at, :items, keyword_init: true)

  def test_builds_a_summary_from_digest_metadata
    digest = Digest.new(
      notification_type: "generic",
      cadence: "weekly",
      period_starts_at: Time.utc(2026, 7, 6),
      period_ends_at: Time.utc(2026, 7, 13),
      items: [Object.new, Object.new]
    )

    summary = RecordingStudioNotifications::Services::DigestSummaryPresenter.call(digest: digest)

    assert_equal "Weekly summary: Generic notification (2)", summary[:title]
    assert_equal "2 generic notification events from 2026-07-06 to 2026-07-12.", summary[:body]
    assert_equal :bell, summary[:icon]
    assert_nil summary[:destination]
  end
end