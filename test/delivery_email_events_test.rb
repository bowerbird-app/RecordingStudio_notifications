# frozen_string_literal: true

require "test_helper"
require "active_record"
require "active_support/core_ext/time/zones"
require_relative "../app/models/recording_studio_notifications/application_record"
require_relative "../app/models/recording_studio_notifications/delivery"

class DeliveryEmailEventsTest < Minitest::Test
  def setup
    @previous_zone = Time.zone
    Time.zone = "UTC"
    @delivery = RecordingStudioNotifications::Delivery.allocate
    @metadata = {}
    metadata = @metadata
    @delivery.define_singleton_method(:metadata) { metadata }
  end

  def teardown
    Time.zone = @previous_zone
  end

  def test_predicate_is_false_before_a_timestamp_and_true_after
    refute @delivery.email_event_applied?(:opened)
    assert_nil @delivery.email_event_at(:opened)

    @metadata["email_opened_at"] = "2026-03-01T12:00:00Z"

    assert @delivery.email_event_applied?(:opened)
    assert @delivery.email_event_applied?(" opened ")
    assert_equal "2026-03-01T12:00:00Z", @delivery.email_event_at(:opened).iso8601
    refute @delivery.email_event_applied?(:clicked)
  end

  def test_each_email_event_reads_its_own_timestamp
    stamps = {
      opened: "email_opened_at",
      clicked: "email_clicked_at",
      bounced: "email_bounced_at",
      complained: "email_complained_at",
      unsubscribed: "email_unsubscribed_at"
    }

    stamps.each_with_index do |(type, key), index|
      @metadata[key] = Time.utc(2026, 3, index + 1, 12, 0, 0).iso8601

      assert @delivery.email_event_applied?(type)
      assert_equal @metadata[key], @delivery.email_event_at(type.to_s).iso8601
    end
  end

  def test_malformed_metadata_is_not_applied
    @metadata["email_opened_at"] = "not-a-time"

    assert_nil @delivery.email_event_at(:opened)
    refute @delivery.email_event_applied?(:opened)
  end

  def test_mark_replaces_an_unparseable_timestamp_and_keeps_a_valid_one
    @metadata["email_opened_at"] = "not-a-time"
    @metadata["keep"] = "yes"
    metadata = @metadata
    @delivery.define_singleton_method(:update!) do |**attributes|
      metadata.replace(attributes.fetch(:metadata))
      self
    end

    at = Time.utc(2026, 3, 1, 12, 0, 0)
    @delivery.mark_email_opened!(at: at)

    assert_equal at.iso8601, @metadata["email_opened_at"]
    assert_equal "yes", @metadata["keep"]
    assert @delivery.email_event_applied?(:opened)

    later = Time.utc(2026, 3, 2, 12, 0, 0)
    @delivery.mark_email_opened!(at: later)

    assert_equal at.iso8601, @metadata["email_opened_at"]
  end

  def test_unknown_email_event_raises
    applied = assert_raises(ArgumentError) { @delivery.email_event_applied?(:sent) }
    at = assert_raises(ArgumentError) { @delivery.email_event_at("email_opened") }

    assert_equal "unknown email event: sent", applied.message
    assert_equal "unknown email event: email_opened", at.message
  end
end
