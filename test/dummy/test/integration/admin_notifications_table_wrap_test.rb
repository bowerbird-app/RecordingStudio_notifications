# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminNotificationsTableWrapTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin-notifications-table-#{SecureRandom.uuid}@example.test") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    grant_admin_access_for_test!
    sign_in @user

    RecordingStudioNotifications::Notification.create!(
      recipient: @user,
      notification_type: :workspace_change,
      title: "Wrapped admin table row",
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  test "notifications admin table is wrapped in a two-column grid and outlined card" do
    get "/admin/screens/recording_studio_notifications_all_notifications"

    assert_response :success
    assert_includes response.body, "All notifications"
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "grid-cols-1 md:grid-cols-2"
    assert_includes response.body, "border-2 border-[var(--card-border-color)]"

    get "/admin/screens/recording_studio_notifications_all_notifications/table"

    assert_response :success
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "grid-cols-1 md:grid-cols-2"
    assert_includes response.body, "border-2 border-[var(--card-border-color)]"
    assert_includes response.body, "Wrapped admin table row"
    assert_includes response.body, "Table data"
    assert_operator response.body.index("grid-cols-1 md:grid-cols-2"),
                    :<,
                    response.body.index("border-2 border-[var(--card-border-color)]")
    assert_operator response.body.index("border-2 border-[var(--card-border-color)]"),
                    :<,
                    response.body.index("Wrapped admin table row")
  end

  test "other admin tables are not wrapped in the notifications grid card" do
    get "/admin/screens/admin_activity_logs/table"

    assert_response :success
    assert_includes response.body, 'id="screen-table"'
    refute_includes response.body, "grid-cols-1 md:grid-cols-2"
    refute_includes response.body, "border-2 border-[var(--card-border-color)]"
  end

  private

  def grant_admin_access_for_test!
    admin_root = AdminRoot.first_or_create!
    recording = RecordingStudio.root_recording_for(admin_root)
    previous_access_authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(recording:, **) { recording.present? }

    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: @user,
      role: :admin,
      manager_actor: @user
    )

    raise "Failed to grant access in test: #{result.error}" if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous_access_authorizer
  end
end
