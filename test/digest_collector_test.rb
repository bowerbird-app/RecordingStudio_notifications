# frozen_string_literal: true

require "test_helper"

class DigestCollectorTest < Minitest::Test
  def setup
    @at = Time.utc(2026, 7, 10, 14, 30)
  end

  def test_calculates_daily_weekly_and_monthly_calendar_periods
    assert_period :daily, "2026-07-10 00:00:00", "2026-07-11 00:00:00"
    assert_period :weekly, "2026-07-06 00:00:00", "2026-07-13 00:00:00"
    assert_period :monthly, "2026-07-01 00:00:00", "2026-08-01 00:00:00"
  end

  def test_calculates_stable_alternate_day_and_biweekly_periods
    alternate_day_period = period_for(:every_other_day)
    biweekly_period = period_for(:biweekly)

    assert_equal 2, alternate_day_period.ends_at.to_date - alternate_day_period.starts_at.to_date
    assert_equal alternate_day_period.starts_at, period_for(:every_other_day, @at - 86_400).starts_at
    assert_equal 14, biweekly_period.ends_at.to_date - biweekly_period.starts_at.to_date
    assert_equal 1, biweekly_period.starts_at.wday
    assert_operator biweekly_period.starts_at, :<=, @at
    assert_operator biweekly_period.ends_at, :>, @at
  end

  def test_rejects_immediate_cadence_as_a_digest_period
    assert_raises(ArgumentError) do
      RecordingStudioNotifications::Services::DigestCollector.period_for(
        cadence: :every_notification,
        at: @at
      )
    end
  end

  private

  def assert_period(cadence, starts_at, ends_at)
    digest_period = period_for(cadence)

    assert_equal Time.utc(*starts_at.split(/[- :]/).map(&:to_i)), digest_period.starts_at
    assert_equal Time.utc(*ends_at.split(/[- :]/).map(&:to_i)), digest_period.ends_at
  end

  def period_for(cadence, at = @at)
    RecordingStudioNotifications::Services::DigestCollector.period_for(cadence: cadence, at: at)
  end
end