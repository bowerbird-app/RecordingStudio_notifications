# frozen_string_literal: true

require "test_helper"

class NotificationsApiTest < ActionDispatch::IntegrationTest
  API_ROOT = "/recording_studio_api/api/v1"

  setup do
    @owner = User.create!(
      email: "notifications-api-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @owner
    @workspace = Workspace.create!(name: "Notifications API #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    bootstrap_owner!(@root, @owner)
    @issued = issue_token_for(@owner, @root)
    @actor = @issued.fetch(:api_client)
    @other = User.create!(
      email: "notifications-api-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications::Preference.set_cadence!(
      recipient: @actor,
      notification_type: :page_comment,
      cadence: :individual
    )
    @notification = notify!(recipient: @actor, title: "API inbox #{SecureRandom.hex(4)}")
    @foreign = notify!(recipient: @other, title: "Someone else #{SecureRandom.hex(4)}")
  end

  teardown do
    Current.actor = nil
  end

  test "catalog lists every notifications endpoint" do
    RecordingStudioNotifications::Api::ENDPOINTS.each do |endpoint|
      registered = RecordingStudioApi.registered_endpoint(endpoint.fetch(:name))
      assert registered, "missing #{endpoint.fetch(:name)}"
      assert_equal endpoint.fetch(:http_verb), registered.http_verb
      assert_equal endpoint.fetch(:path), registered.path
      assert registered.openapi[:title]
      assert registered.openapi[:summary]
      assert registered.openapi[:description]
    end
  end

  test "inbox index show and member actions work for the current actor" do
    get "#{API_ROOT}/notifications",
        params: { page: 1, per_page: 20 },
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json

    assert_response :success
    payload = response.parsed_body
    ids = payload.fetch("records").map { |row| row.fetch("id") }
    assert_includes ids, @notification.id
    refute_includes ids, @foreign.id
    assert_equal 1, payload.fetch("meta").fetch("page")
    assert_equal 20, payload.fetch("meta").fetch("per_page")

    get "#{API_ROOT}/notifications/#{@notification.id}",
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    assert_equal @notification.title, response.parsed_body.fetch("title")

    post "#{API_ROOT}/notifications/#{@notification.id}/mark_read",
         headers: bearer_headers(@issued.fetch(:token)),
         as: :json
    assert_response :success
    assert @notification.reload.read?

    post "#{API_ROOT}/notifications/#{@notification.id}/mark_unread",
         headers: bearer_headers(@issued.fetch(:token)),
         as: :json
    assert_response :success
    assert @notification.reload.unread?

    post "#{API_ROOT}/notifications/#{@notification.id}/unarchive",
         headers: bearer_headers(@issued.fetch(:token)),
         as: :json
    assert_response :success
    refute @notification.reload.archived?

    post "#{API_ROOT}/notifications/#{@notification.id}/archive",
         headers: bearer_headers(@issued.fetch(:token)),
         as: :json
    assert_response :success
    assert @notification.reload.archived?
  end

  test "archived and delivery-only notifications are omitted and not reachable" do
    archived = notify!(recipient: @actor, title: "Archived #{SecureRandom.hex(4)}")
    archived.archive!
    delivery_only = notify!(
      recipient: @actor,
      title: "Email only #{SecureRandom.hex(4)}",
      inbox: false,
      channels: [ :email ]
    )

    get "#{API_ROOT}/notifications",
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    ids = response.parsed_body.fetch("records").map { |row| row.fetch("id") }
    refute_includes ids, archived.id
    refute_includes ids, delivery_only.id
    assert_includes ids, @notification.id

    [
      archived,
      delivery_only
    ].each do |hidden|
      get "#{API_ROOT}/notifications/#{hidden.id}",
          headers: bearer_headers(@issued.fetch(:token)),
          as: :json
      assert_response :not_found, "show should 404 for #{hidden.title}"

      %i[mark_read mark_unread archive unarchive].each do |action|
        post "#{API_ROOT}/notifications/#{hidden.id}/#{action}",
             headers: bearer_headers(@issued.fetch(:token)),
             as: :json
        assert_response :not_found, "#{action} should 404 for #{hidden.title}"
      end
    end
  end

  test "inbox pages default, clamp, and the next page is disjoint" do
    cap = RecordingStudioNotifications::NotificationsController::PER_PAGE
    extras = cap.times.map do |index|
      notify!(recipient: @actor, title: "Page row #{index} #{SecureRandom.hex(4)}")
    end
    inbox_ids = ([@notification] + extras).map(&:id)

    get "#{API_ROOT}/notifications",
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    default_page = response.parsed_body
    default_ids = default_page.fetch("records").map { |row| row.fetch("id") }
    assert_equal cap, default_page.fetch("meta").fetch("per_page")
    assert_equal cap, default_ids.size
    assert_equal inbox_ids.size, default_page.fetch("meta").fetch("total_count")

    get "#{API_ROOT}/notifications",
        params: { per_page: cap + 50 },
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    clamped = response.parsed_body
    assert_equal cap, clamped.fetch("meta").fetch("per_page")
    assert_equal cap, clamped.fetch("records").size

    get "#{API_ROOT}/notifications",
        params: { page: 2 },
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    next_page = response.parsed_body
    next_ids = next_page.fetch("records").map { |row| row.fetch("id") }
    assert_equal cap, next_page.fetch("meta").fetch("per_page")
    assert_equal inbox_ids.size - cap, next_ids.size
    assert_empty default_ids & next_ids
    assert_equal inbox_ids.sort, (default_ids + next_ids).sort
  end

  test "preferences get and update work for the current actor" do
    get "#{API_ROOT}/notifications/preferences",
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :success
    assert response.parsed_body.key?("records")

    patch "#{API_ROOT}/notifications/preferences",
          headers: bearer_headers(@issued.fetch(:token)),
          params: { notification_type: "page_comment", channel: "email", enabled: false },
          as: :json
    assert_response :success
    refute RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @actor,
      notification_type: :page_comment,
      channel: :email,
      default: true
    )

    patch "#{API_ROOT}/notifications/preferences",
          headers: bearer_headers(@issued.fetch(:token)),
          params: { notification_type: "page_comment", cadence: "weekly" },
          as: :json
    assert_response :success
    assert_equal :weekly, RecordingStudioNotifications::Preference.cadence_for(
      recipient: @actor,
      notification_type: :page_comment,
      default: :daily
    )
  end

  test "denied actor cannot read or change notifications" do
    RecordingStudio::Access.where(id: @issued.fetch(:access_recording).recordable_id).update_all(role: "")
    refute RecordingStudioAccessible.authorized?(
      actor: @issued.fetch(:access_recording).recordable.reload.actor,
      recording: @root,
      role: :view
    )

    [
      [:get, "#{API_ROOT}/notifications", {}],
      [:get, "#{API_ROOT}/notifications/#{@notification.id}", {}],
      [:post, "#{API_ROOT}/notifications/#{@notification.id}/mark_read", {}],
      [:post, "#{API_ROOT}/notifications/#{@notification.id}/mark_unread", {}],
      [:post, "#{API_ROOT}/notifications/#{@notification.id}/archive", {}],
      [:post, "#{API_ROOT}/notifications/#{@notification.id}/unarchive", {}],
      [:get, "#{API_ROOT}/notifications/preferences", {}],
      [:patch, "#{API_ROOT}/notifications/preferences", { notification_type: "page_comment", channel: "email", enabled: false }]
    ].each do |verb, path, params|
      send(verb, path, params: params, headers: bearer_headers(@issued.fetch(:token)), as: :json)
      assert_response :forbidden, "#{verb.upcase} #{path} should be forbidden"
    end
  end

  test "another recipient's notification is not visible" do
    get "#{API_ROOT}/notifications/#{@foreign.id}",
        headers: bearer_headers(@issued.fetch(:token)),
        as: :json
    assert_response :not_found

    [
      :mark_read,
      :mark_unread,
      :archive,
      :unarchive
    ].each do |action|
      post "#{API_ROOT}/notifications/#{@foreign.id}/#{action}",
           headers: bearer_headers(@issued.fetch(:token)),
           as: :json
      assert_response :not_found, "#{action} should 404 for another recipient"
    end
  end

  private

  def notify!(recipient:, title:, inbox: true, channels: nil)
    RecordingStudioNotifications.notify(
      notification_type: :page_comment,
      recipient: recipient,
      actor: @owner,
      root_recording: @root,
      title: title,
      inbox: inbox,
      channels: channels,
      deliver_later: false,
      idempotency_key: "notifications-api-#{SecureRandom.uuid}"
    )
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?
  end

  def issue_token_for(actor, root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: root,
      manager_actor: actor,
      role: :view,
      name: "Notifications API #{SecureRandom.hex(4)}"
    )
    raise provision.error unless provision.success?

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provision.value.fetch(:credential).oauth_client_id,
      client_secret: provision.value.fetch(:token)
    )
    raise token_result.error unless token_result.success?

    {
      token: token_result.value.fetch(:access_token),
      access_recording: provision.value.fetch(:access_recording),
      api_client: provision.value.fetch(:api_client)
    }
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
