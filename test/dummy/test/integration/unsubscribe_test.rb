# frozen_string_literal: true

require "test_helper"

class UnsubscribeTwinRecipient < ApplicationRecord
  self.table_name = "users"
end

class UnsubscribeTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "unsubscribe-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :digest_mail,
      label: "Digest mail",
      scope: :global,
      default_channels: %i[in_app email],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    RecordingStudioNotifications.notification_types.register(
      :product_mail,
      label: "Product mail",
      scope: :global,
      default_channels: %i[in_app email],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual,
      visible_to: ->(_recipient) { false }
    )
    RecordingStudioNotifications.notification_types.register(
      :required_mail,
      label: "Required mail",
      scope: :global,
      default_channels: [:email],
      required_channels: [:email],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
  end

  test "get confirms without writing and the form post then shows the done page" do
    path = unsubscribe_path_for(@user, :digest_mail, :email)

    assert_no_difference -> { RecordingStudioNotifications::Preference.count } do
      get path
    end

    assert_response :success
    assert_select "h1", text: "Stop these emails?"
    assert_select "p", text: "Digest mail by email."
    assert_select "button", text: "Unsubscribe"
    refute_match %r{/users/sign_in}, response.headers["Location"].to_s

    post path
    assert_response :see_other
    assert_not_predicate preference(@user, :digest_mail, :email), :enabled
    follow_redirect!
    assert_response :success
    assert_select "h1", text: "You're unsubscribed."
    assert_select "button", count: 0

    assert_no_difference -> { RecordingStudioNotifications::Preference.where(enabled: false).count } do
      post path
    end
    follow_redirect!
    assert_select "h1", text: "You're unsubscribed."
    assert_not_predicate preference(@user, :digest_mail, :email), :enabled
  end

  test "an already disabled preference omits the button" do
    RecordingStudioNotifications::Preference.set!(
      recipient: @user, notification_type: :digest_mail, channel: :email, enabled: false
    )

    get unsubscribe_path_for(@user, :digest_mail, :email)

    assert_response :success
    assert_select "h1", text: "You're already unsubscribed."
    assert_select "button", count: 0
  end

  test "one click post writes and returns 200 without a session cookie" do
    path = unsubscribe_path_for(@user, :digest_mail, :email)

    post path, params: { "List-Unsubscribe" => "One-Click", "extra" => "1" }

    assert_response :success
    assert_equal "Unsubscribed.", response.body
    assert_not response.headers["Set-Cookie"].present?
    assert_not_predicate preference(@user, :digest_mail, :email), :enabled

    other = User.create!(
      email: "unsubscribe-raw-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    post unsubscribe_path_for(other, :digest_mail, :email),
         params: "List-Unsubscribe=One-Click",
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :success
    assert_equal "Unsubscribed.", response.body
    assert_not_predicate preference(other, :digest_mail, :email), :enabled
  end

  test "a token for one type and channel leaves the others alone" do
    post unsubscribe_path_for(@user, :digest_mail, :email)

    assert_not_predicate preference(@user, :digest_mail, :email), :enabled
    assert RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @user, notification_type: :product_mail, channel: :email, default: true
    )
    assert RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @user, notification_type: :digest_mail, channel: :in_app, default: true
    )
  end

  test "visible_to does not block the unsubscribe link" do
    post unsubscribe_path_for(@user, :product_mail, :email)

    assert_response :see_other
    assert_not_predicate preference(@user, :product_mail, :email), :enabled
  end

  test "expired tampered and unknown recipient tokens write nothing" do
    purpose = RecordingStudioNotifications.unsubscribe_purpose(:digest_mail, :email)
    expired = @user.to_sgid(for: purpose, expires_in: 1.minute).to_s
    travel 2.minutes do
      assert_no_difference -> { RecordingStudioNotifications::Preference.count } do
        get unsubscribe_request(:digest_mail, :email, expired)
      end
    end
    assert_response :not_found
    assert_select "h1", text: "This unsubscribe link doesn't work."
    assert_select "a[href='#{RecordingStudioNotifications::Engine.routes.url_helpers.settings_path}']",
                  text: "Sign in to settings"

    tampered = RecordingStudioNotifications.unsubscribe_token(
      recipient: @user, notification_type: :digest_mail, channel: :email
    )
    get unsubscribe_request(:digest_mail, :email, "#{tampered}x")
    assert_response :not_found

    gone = User.create!(
      email: "unsubscribe-gone-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    gone_path = unsubscribe_path_for(gone, :digest_mail, :email)
    gone.destroy!
    get gone_path
    assert_response :not_found
    assert_equal 0, RecordingStudioNotifications::Preference.where(recipient: gone).count
  end

  test "a required channel is explained and the post is rejected" do
    path = unsubscribe_path_for(@user, :required_mail, :email)

    get path
    assert_response :success
    assert_select "h1", text: "This one stays on."
    assert_select "button", count: 0

    assert_no_difference -> { RecordingStudioNotifications::Preference.count } do
      post path
    end
    assert_response :unprocessable_entity

    post path, params: { "List-Unsubscribe" => "One-Click" }
    assert_response :unprocessable_entity
    assert RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @user, notification_type: :required_mail, channel: :email, default: true
    )
  end

  test "two recipient classes with the same id cannot use each other's token" do
    twin = UnsubscribeTwinRecipient.find(@user.id)
    refute_equal(
      RecordingStudioNotifications.unsubscribe_token(recipient: @user, notification_type: :digest_mail, channel: :email),
      RecordingStudioNotifications.unsubscribe_token(recipient: twin, notification_type: :digest_mail, channel: :email)
    )

    post unsubscribe_path_for(@user, :digest_mail, :email)
    assert_not_predicate preference(@user, :digest_mail, :email), :enabled
    assert RecordingStudioNotifications::Preference.enabled_for?(
      recipient: twin, notification_type: :digest_mail, channel: :email, default: true
    )

    post unsubscribe_path_for(twin, :digest_mail, :email)
    assert_not_predicate preference(twin, :digest_mail, :email), :enabled
    assert_not_predicate preference(@user, :digest_mail, :email), :enabled
  end

  test "the helper url round trips through the verifier" do
    url = RecordingStudioNotifications.unsubscribe_url(
      recipient: @user, notification_type: :digest_mail, channel: :email
    )
    uri = URI.parse(url)
    token = Rack::Utils.parse_query(uri.query).fetch("token")
    located = GlobalID::Locator.locate_signed(
      token,
      for: RecordingStudioNotifications.unsubscribe_purpose(:digest_mail, :email)
    )
    headers = RecordingStudioNotifications.list_unsubscribe_headers(
      recipient: @user, notification_type: :digest_mail, channel: :email
    )
    header_url = headers.fetch("List-Unsubscribe").delete_prefix("<").delete_suffix(">")

    assert_equal "example.com", uri.host
    assert_equal "/notifications/unsubscribe/digest_mail/email", uri.path
    assert_equal @user, located
    assert_match %r{\Ahttp://example.com/notifications/unsubscribe/digest_mail/email\?token=.+\z}, header_url
    assert_equal @user, GlobalID::Locator.locate_signed(
      Rack::Utils.parse_query(URI.parse(header_url).query).fetch("token"),
      for: RecordingStudioNotifications.unsubscribe_purpose(:digest_mail, :email)
    )
    assert_equal "List-Unsubscribe=One-Click", headers.fetch("List-Unsubscribe-Post")

    get "#{uri.path}?#{uri.query}"
    assert_response :success
    assert_select "h1", text: "Stop these emails?"
  end

  test "a mismatched type in the url does not write" do
    url = RecordingStudioNotifications.unsubscribe_url(
      recipient: @user, notification_type: :digest_mail, channel: :email
    )
    token = Rack::Utils.parse_query(URI.parse(url).query).fetch("token")

    assert_no_difference -> { RecordingStudioNotifications::Preference.count } do
      post unsubscribe_request(:product_mail, :email, token)
    end
    assert_response :not_found
  end

  private

  def unsubscribe_path_for(recipient, notification_type, channel)
    url = RecordingStudioNotifications.unsubscribe_url(recipient:, notification_type:, channel:)
    uri = URI.parse(url)
    "#{uri.path}?#{uri.query}"
  end

  def unsubscribe_request(notification_type, channel, token)
    "/notifications/unsubscribe/#{notification_type}/#{channel}?#{Rack::Utils.build_query(token: token)}"
  end

  def preference(recipient, notification_type, channel)
    RecordingStudioNotifications::Preference.find_by!(
      recipient: recipient,
      notification_type: notification_type.to_s,
      channel: channel.to_s
    )
  end
end
