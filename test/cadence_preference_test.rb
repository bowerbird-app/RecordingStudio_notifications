# frozen_string_literal: true

require "test_helper"
require "active_record"
require_relative "../app/models/recording_studio_notifications/application_record"
require_relative "../app/models/recording_studio_notifications/cadence_preference"

class CadencePreferenceTest < Minitest::Test
  def test_missing_cadence_table_preserves_the_registered_default
    RecordingStudioNotifications::CadencePreference.stub(:table_exists?, false) do
      assert_equal :every_notification,
                   RecordingStudioNotifications::CadencePreference.cadence_for(
                     recipient: Object.new,
                     notification_type: :page_comment,
                     default: :every_notification
                   )
    end
  end
end