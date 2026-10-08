# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CustomerI18nTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
  end

  test "language selector sits in the dummy top nav left of the notifications menu" do
    get "/"

    assert_response :success
    assert_select "form[action='/recording_studio_internationalization/locale']"
    assert_includes response.body, "English"
    assert_includes response.body, "Français"
    assert_select "html[lang='en']"
    selector_at = response.body.index("dummy-language-selector")
    menu_at = response.body.index("recording-studio-notifications--notification-polling")
    assert selector_at
    assert menu_at
    assert_operator selector_at, :<, menu_at
  end

  test "inbox and settings stay English until the host locale changes" do
    get "/notifications"

    assert_response :success
    assert_includes response.body, ">Notifications</h1>"
    assert_includes response.body, ">Settings</span>"
    assert_select "html[lang='en']"

    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, "Notification settings"
    assert_includes response.body, ">Channel</label>"
    assert_includes response.body, ">Frequency</label>"
    assert_includes response.body, "Save settings"
    assert_select "html[lang='en']"
  end

  test "dummy French locale renders the notifications list and settings" do
    switch_to_french

    get "/notifications"

    assert_response :success
    assert_select "html[lang='fr']"
    assert_includes response.body, ">Notifications</h1>"
    assert_includes response.body, ">Réglages</span>"
    refute_includes response.body, ">Settings</span>"

    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, "Réglages des notifications"
    assert_includes response.body, ">Canal</label>"
    assert_includes response.body, ">Fréquence</label>"
    assert_includes response.body, "Enregistrer"
    refute_includes response.body, "Notification settings"
    refute_includes response.body, "Save settings"
  end

  test "menu payload follows French for chrome and leaves stored titles alone" do
    stored_title = "Jo likes the new heading"
    RecordingStudioNotifications.notify(
      notification_type: :system_announcement,
      recipient: @user,
      title: stored_title,
      body: "Stored body stays in the language it was written.",
      url: "/",
      idempotency_key: "i18n-menu-#{SecureRandom.uuid}"
    )

    switch_to_french
    get "/notifications/notifications/menu.json"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("menu_html"), stored_title
    assert_includes payload.fetch("menu_html"), "Voir toutes les notifications"
    assert_includes payload.fetch("menu_html"), "Notifications"
  end

  test "menu component text overrides still win" do
    html = ApplicationController.render(
      partial: "recording_studio_notifications/notifications/menu_component",
      locals: {
        unread_count: 0,
        notifications: [],
        see_all_href: "/notifications",
        bell_label: "Acme alerts",
        empty_text: "Host empty"
      }
    )

    assert_includes html, "Acme alerts"
    assert_includes html, "Host empty"
    refute_includes html, "No recent notifications"
  end

  private

  def switch_to_french
    patch "/recording_studio_internationalization/locale", params: { locale: "fr", return_to: "/" }
    follow_redirect!
  end
end
