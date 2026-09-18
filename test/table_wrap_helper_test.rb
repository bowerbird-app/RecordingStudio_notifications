# frozen_string_literal: true

require "test_helper"
require "recording_studio_notifications/admin/table_wrap_helper"

class TableWrapHelperTest < Minitest::Test
  class Host
    include RecordingStudioNotifications::Admin::TableWrapHelper
  end

  def setup
    @helper = Host.new
  end

  def test_wraps_only_the_notifications_admin_screen
    notifications = Struct.new(:key).new("recording_studio_notifications_all_notifications")
    other = Struct.new(:key).new("admin_activity_logs")

    assert @helper.notifications_admin_table?(notifications)
    refute @helper.notifications_admin_table?(other)
    refute @helper.notifications_admin_table?(nil)
  end

  def test_admin_table_partials_use_the_wrap_helper
    table_frame = File.read(File.expand_path("../app/views/recording_studio_admin/screens/_table_frame.html.erb",
                                             __dir__))
    placeholder = File.read(File.expand_path("../app/views/recording_studio_admin/screens/_table_placeholder.html.erb",
                                             __dir__))
    helper = File.read(File.expand_path("../lib/recording_studio_notifications/admin/table_wrap_helper.rb", __dir__))

    assert_includes table_frame, "wrap_recording_studio_notifications_admin_table"
    assert_includes table_frame, 'render "recording_studio_admin/screens/table"'
    assert_includes placeholder, "wrap_recording_studio_notifications_admin_table"
    assert_includes helper, "FlatPack::Grid::Component.new(cols: 2"
    assert_includes helper, "FlatPack::Card::Component.new(style: :outlined)"
  end
end
