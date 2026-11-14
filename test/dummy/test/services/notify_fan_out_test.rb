# frozen_string_literal: true

require "test_helper"

class NotifyFanOutTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class << self
    attr_accessor :email_prefix
  end

  setup do
    @actor = create_user("fan-actor")
    @original_rollup = RecordingStudioNotifications.configuration.rollup_delivery_enabled
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = true
    register_type(:fan_out_notice)
    RecordingStudioNotifications.register_recipient_scope(:fan_out_test_users) do
      User.where("email LIKE ?", "#{NotifyFanOutTest.email_prefix}-%")
    end
    RecordingStudioNotifications.register_recipient_scope(:fan_out_fixed) { @fixed_recipients }
  end

  teardown do
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = @original_rollup
    %i[before_service around_service after_service].each do |hook|
      RecordingStudioNotifications.configuration.hooks.clear(hook)
    end
    self.class.email_prefix = nil
    remove_time_zone
  end

  test "enqueue stores global ids and a scope name and writes nothing yet" do
    notice = SystemNotification.create!(title: "Board", body: "Hello everyone", creator: @actor)
    self.class.email_prefix = "fan-enqueue"
    create_users("fan-enqueue", 2)

    assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
      @job = RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :fan_out_test_users,
        notification_type: :fan_out_notice,
        actor: @actor,
        notifiable: notice,
        title: "Board copy",
        metadata: { "wave" => "one" },
        idempotency_key: "fan-enqueue-key"
      )
    end

    assert_instance_of RecordingStudioNotifications::FanOutJob, @job
    payload = @job.arguments.first
    assert_equal "fan_out_test_users", payload.fetch("recipient_scope")
    assert_equal "fan-enqueue-key", payload.fetch("idempotency_key")
    assert_equal @actor.to_global_id.to_s, payload.fetch("actor_gid")
    assert_equal notice.to_global_id.to_s, payload.fetch("notifiable_gid")
    assert_nil payload.fetch("recording_gid")
    assert_nil payload.fetch("root_recording_gid")
    assert payload.values.none? { |value| value.is_a?(ActiveRecord::Base) || value.is_a?(ActiveRecord::Relation) }

    clear_enqueued_jobs
    @job.perform_now
    notification = RecordingStudioNotifications::Notification.find_by!(idempotency_key: "fan-enqueue-key")
    assert_equal @actor, notification.actor
    assert_equal notice, notification.notifiable
    assert_nil notification.recording_id
    assert_nil notification.root_recording_id
    assert_equal "one", notification.metadata["wave"]
    assert_equal 1, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")
    assert_equal 0, jobs_named("RecordingStudioNotifications::DeliveryJob")
  end

  test "delivery job calls the adapter once per immediate delivery" do
    calls = register_mail_adapter
    register_type(:fan_out_mail_notice, channels: [:fan_out_mail])
    create_users("fan-deliver", 3)

    run_fan_out(prefix: "fan-deliver", notification_type: :fan_out_mail_notice, idempotency_key: "fan-deliver")
    perform_enqueued_jobs

    notifications = RecordingStudioNotifications::Notification.where(idempotency_key: "fan-deliver")
    assert_equal 3, notifications.count
    assert_equal notifications.flat_map { |notification| notification.deliveries.map(&:id) }.sort, calls.sort
    assert notifications.all? { |notification| notification.deliveries.sole.delivered? }
  end

  test "retry is idempotent and the first inbox flag wins" do
    register_mail_adapter
    register_type(:fan_out_inbox, channels: %i[in_app fan_out_mail])
    create_users("fan-retry", 2)
    attributes = { prefix: "fan-retry", notification_type: :fan_out_inbox, idempotency_key: "fan-retry", title: "First" }

    run_fan_out(**attributes, inbox: false)
    perform_enqueued_jobs
    first = RecordingStudioNotifications::Notification.where(idempotency_key: "fan-retry").order(:id).to_a
    assert_equal [false, false], first.map(&:inbox)
    assert_equal [%w[fan_out_mail], %w[fan_out_mail]], first.map { |notification| notification.deliveries.pluck(:channel).sort }
    assert first.all? { |notification| notification.deliveries.sole.delivered? }

    assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
      assert_no_difference -> { RecordingStudioNotifications::Delivery.count } do
        run_fan_out(**attributes, inbox: true, title: "Second", channels: %i[in_app fan_out_mail])
      end
    end
    assert_equal 0, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")

    reloaded = first.map(&:reload)
    assert_equal ["First", "First"], reloaded.map(&:title)
    assert_equal [false, false], reloaded.map(&:inbox)
    assert_equal [%w[fan_out_mail], %w[fan_out_mail]], reloaded.map { |notification| notification.deliveries.pluck(:channel).sort }
  end

  test "retry after a crash between commit and enqueue sends each delivery once" do
    calls = register_mail_adapter
    register_type(:fan_out_crash_mail, channels: [:fan_out_mail])
    create_users("fan-crash", 3)
    payload = fan_out_payload(prefix: "fan-crash", notification_type: :fan_out_crash_mail, idempotency_key: "fan-crash")
    clear_enqueued_jobs

    crashed = RecordingStudioNotifications::Services::FanOut.new(payload)
    crashed.define_singleton_method(:enqueue_deliveries) { |*| raise "crash before enqueue" }
    events = 0
    callback = ->(*) { events += 1 }

    ActiveSupport::Notifications.subscribed(callback, "notify.recording_studio_notifications") do
      error = assert_raises(RuntimeError) { crashed.call }
      assert_equal "crash before enqueue", error.message
    end

    assert_equal 3, events
    assert_equal 3, RecordingStudioNotifications::Notification.where(idempotency_key: "fan-crash").count
    assert_equal 0, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")
    assert_empty calls

    events = 0
    ActiveSupport::Notifications.subscribed(callback, "notify.recording_studio_notifications") do
      assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
        assert_no_difference -> { RecordingStudioNotifications::Delivery.count } do
          clear_enqueued_jobs
          RecordingStudioNotifications::Services::FanOut.perform(payload)
        end
      end
    end

    assert_equal 0, events
    assert_equal 1, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")
    perform_enqueued_jobs
    assert_equal 3, calls.uniq.size
    assert_equal calls.uniq.size, calls.size

    RecordingStudioNotifications::FanOutDeliveryJob.perform_now(calls.dup)
    delivery = RecordingStudioNotifications::Delivery.find(calls.first)
    delivery.update!(status: "processing")
    RecordingStudioNotifications::FanOutDeliveryJob.perform_now([delivery.id])
    RecordingStudioNotifications::DeliveryJob.perform_now(delivery.notification_id)
    delivery.update!(status: "failed", error_message: "stopped")
    RecordingStudioNotifications::FanOutDeliveryJob.perform_now([delivery.id])
    assert_equal 3, calls.size
    assert_equal calls.uniq.sort, calls.sort
  end

  test "inbox false skips in_app and required in_app raises" do
    register_mail_adapter
    register_type(:fan_out_hidden, channels: %i[in_app fan_out_mail])
    create_users("fan-hidden", 1)

    run_fan_out(prefix: "fan-hidden", notification_type: :fan_out_hidden, idempotency_key: "fan-hidden", inbox: false)
    hidden = RecordingStudioNotifications::Notification.find_by!(idempotency_key: "fan-hidden")
    assert_equal false, hidden.inbox
    assert_equal ["fan_out_mail"], hidden.deliveries.pluck(:channel)

    register_type(:fan_out_required_in_app, channels: [:in_app], required: [:in_app])
    error = assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-hidden", notification_type: :fan_out_required_in_app, idempotency_key: "fan-required", inbox: false)
    end
    assert_includes error.message, "inbox cannot be false"
    assert_nil RecordingStudioNotifications::Notification.find_by(idempotency_key: "fan-required")
  end

  test "deferred cadence stores rollup metadata and enqueues no delivery job" do
    register_type(:fan_out_weekly, channels: [:in_app], cadence: :weekly, cadences: %i[individual weekly])
    tokyo, honolulu = zoned_users
    @fixed_recipients = [tokyo, honolulu]

    travel_to Time.utc(2026, 7, 6, 2) do
      assert_no_enqueued_jobs only: RecordingStudioNotifications::FanOutDeliveryJob do
        assert_no_enqueued_jobs only: RecordingStudioNotifications::RollupDeliveryJob do
          run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_weekly, idempotency_key: "fan-weekly")
        end
      end
    end

    deliveries = RecordingStudioNotifications::Delivery.joins(:notification)
                                                       .where(recording_studio_notifications_notifications: { idempotency_key: "fan-weekly" })
    assert_equal 2, deliveries.count
    assert deliveries.all?(&:deferred_rollup?)
    starts = deliveries.map { |delivery| delivery.metadata["period_starts_at"] }.uniq
    assert_equal 2, starts.size
    assert_equal %w[weekly], deliveries.map { |delivery| delivery.metadata["cadence"] }.uniq
  end

  test "a weekly recipient is deferred and an individual recipient is enqueued once" do
    register_type(:fan_out_mixed, channels: [:in_app], cadence: :individual, cadences: %i[individual weekly])
    weekly = create_user("fan-mixed-weekly")
    immediate = create_user("fan-mixed-now")
    @fixed_recipients = [weekly, immediate]
    RecordingStudioNotifications::Preference.set_cadence!(
      recipient: weekly, notification_type: :fan_out_mixed, cadence: :weekly
    )

    run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_mixed, idempotency_key: "fan-mixed")

    weekly_delivery = RecordingStudioNotifications::Notification.find_by!(recipient: weekly).deliveries.sole
    immediate_delivery = RecordingStudioNotifications::Notification.find_by!(recipient: immediate).deliveries.sole
    assert weekly_delivery.deferred_rollup?
    refute immediate_delivery.deferred_rollup?
    assert_equal 1, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")
    enqueued_ids = enqueued_jobs.flat_map { |entry| Array(entry[:args] || entry["args"]).flatten }.map(&:to_s)
    assert_includes enqueued_ids, immediate_delivery.id.to_s
    refute_includes enqueued_ids, weekly_delivery.id.to_s
  end

  test "preference opt-out and unavailable push skip that recipient" do
    register_mail_adapter
    RecordingStudioNotifications.notification_types.register(
      :fan_out_optional_mail,
      label: "Optional mail",
      scope: :global,
      default_channels: [],
      available_channels: [:fan_out_mail],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    opted_out = create_user("fan-opt-out")
    included = create_user("fan-opt-in")
    RecordingStudioNotifications::Preference.set!(
      recipient: opted_out, notification_type: :fan_out_optional_mail, channel: :fan_out_mail, enabled: false
    )
    @fixed_recipients = [opted_out, included]
    run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_optional_mail, idempotency_key: "fan-opt", channels: [:fan_out_mail])

    assert_nil RecordingStudioNotifications::Notification.find_by(recipient: opted_out, idempotency_key: "fan-opt")
    assert RecordingStudioNotifications::Notification.find_by(recipient: included, idempotency_key: "fan-opt")

    push = Object.new
    push.define_singleton_method(:deliver) { |notification:, delivery:| }
    push.define_singleton_method(:available_for?) { |recipient:, notification:, delivery:| !recipient.email.include?("no-push") }
    RecordingStudioNotifications.channels.register(:fan_out_push, push)
    register_type(:fan_out_push_notice, channels: [:fan_out_push])
    quiet = create_user("fan-no-push")
    loud = create_user("fan-push")
    @fixed_recipients = [quiet, loud]
    run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_push_notice, idempotency_key: "fan-push")

    assert_nil RecordingStudioNotifications::Notification.find_by(recipient: quiet, idempotency_key: "fan-push")
    assert RecordingStudioNotifications::Notification.find_by(recipient: loud, idempotency_key: "fan-push")
  end

  test "hooks and the notify event run once per inserted recipient" do
    create_users("fan-hooks", 3)
    seen = []
    hooks = RecordingStudioNotifications.configuration.hooks
    hooks.before_service { |service, payload| seen << [:before, service, payload.fetch(:recipient).id] }
    hooks.around_service { |service, block| seen << [:around, service]; block.call }
    hooks.after_service { |service, result| seen << [:after, service, result.id] }
    events = 0
    callback = ->(*) { events += 1 }

    ActiveSupport::Notifications.subscribed(callback, "notify.recording_studio_notifications") do
      run_fan_out(prefix: "fan-hooks", idempotency_key: "fan-hooks")
    end

    assert_equal 3, seen.count { |item| item.first == :before }
    assert_equal 3, seen.count { |item| item.first == :around }
    assert_equal 3, seen.count { |item| item.first == :after }
    assert seen.select { |item| item.first != :around }.all? { |item| item[1] == RecordingStudioNotifications::Services::FanOut }
    assert seen.select { |item| item.first == :around }.all? { |item| item[1].is_a?(RecordingStudioNotifications::Services::FanOut) }
    assert_equal 3, events

    seen.clear
    events = 0
    ActiveSupport::Notifications.subscribed(callback, "notify.recording_studio_notifications") do
      run_fan_out(prefix: "fan-hooks", idempotency_key: "fan-hooks")
    end
    assert_empty seen
    assert_equal 0, events
  end

  test "query and enqueue counts stay flat from 20 to 200 recipients" do
    create_users("fan-warm", 1)
    self.class.email_prefix = "fan-warm"
    payload = fan_out_payload(prefix: "fan-warm", idempotency_key: "fan-warm")
    clear_enqueued_jobs
    RecordingStudioNotifications::Services::FanOut.perform(payload)

    small_queries, small_jobs = measure("fan-small", 20, "fan-small")
    large_queries, large_jobs = measure("fan-large", 200, "fan-large")

    assert_equal small_queries, large_queries
    assert_equal 1, small_jobs
    assert_equal small_jobs, large_jobs
    assert_operator small_queries, :<, 30
    assert_equal 20, RecordingStudioNotifications::Notification.where(idempotency_key: "fan-small").count
    assert_equal 200, RecordingStudioNotifications::Notification.where(idempotency_key: "fan-large").count
  end

  test "each chunk of immediate deliveries enqueues one job" do
    create_users("fan-chunks", 5)
    with_chunk_size(2) do
      run_fan_out(prefix: "fan-chunks", idempotency_key: "fan-chunks")
    end

    assert_equal 5, RecordingStudioNotifications::Notification.where(idempotency_key: "fan-chunks").count
    assert_equal 3, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")
  end

  test "enqueue rejects a missing key, an unknown scope, and unknown options" do
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :fan_out_test_users, notification_type: :fan_out_notice, title: "Nope", idempotency_key: " "
      )
    end
    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :missing_people, notification_type: :fan_out_notice, title: "Nope", idempotency_key: "fan-missing"
      )
    end
    assert_includes error.message, "recipient scope is not registered"
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :fan_out_test_users, notification_type: :fan_out_notice, title: "Nope",
        idempotency_key: "fan-unknown", recipient: @actor
      )
    end
    assert_no_enqueued_jobs
  end

  test "shared checks run once and write nothing when they fail" do
    create_users("fan-checks", 2)
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-checks", idempotency_key: "fan-blank", title: " ")
    end
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-checks", idempotency_key: "fan-type", notification_type: :not_registered)
    end
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-checks", idempotency_key: "fan-url", url: "/a\nb")
    end
    register_type(:fan_out_root, scope: :root)
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-checks", idempotency_key: "fan-root", notification_type: :fan_out_root)
    end
    assert_equal 0, RecordingStudioNotifications::Notification.where("idempotency_key LIKE ?", "fan-%").where(recipient: User.where("email LIKE ?", "fan-checks-%")).count

    define_denied_action
    register_type(:fan_out_denied, creation_action: :fan_out_deny)
    Current.actor = @actor
    assert_raises(RecordingStudioNotifications::Services::NotificationAuthorization::NotAuthorized) do
      run_fan_out(prefix: "fan-checks", idempotency_key: "fan-denied", notification_type: :fan_out_denied)
    end
  ensure
    Current.actor = nil
  end

  test "bad arguments and a required channel the adapter refuses are rejected" do
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: " ", notification_type: :fan_out_notice, title: "Nope", idempotency_key: "fan-blank-scope"
      )
    end
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :fan_out_test_users, notification_type: :fan_out_notice, title: "Nope",
        idempotency_key: "fan-metadata", metadata: "nope"
      )
    end
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify_fan_out(
        recipient_scope: :fan_out_test_users, notification_type: :fan_out_notice, title: "Nope",
        idempotency_key: "fan-gid", actor: "not-a-record"
      )
    end

    create_users("fan-more-checks", 1)
    register_mail_adapter
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-more-checks", idempotency_key: "fan-long-url", url: "a" * 2049)
    end
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-more-checks", idempotency_key: "fan-unknown-channel", channels: [:fan_out_missing])
    end
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-more-checks", idempotency_key: "fan-unavailable-channel", channels: [:fan_out_mail])
    end

    immediate = Object.new
    immediate.define_singleton_method(:deliver) { |notification:, delivery:| }
    RecordingStudioNotifications.channels.register(:fan_out_immediate_only, immediate)
    register_type(:fan_out_bad_rollup, channels: [:fan_out_immediate_only], cadence: :weekly, cadences: [:weekly])
    @fixed_recipients = [create_user("fan-bad-rollup")]
    error = assert_raises(ArgumentError) do
      run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_bad_rollup, idempotency_key: "fan-bad-rollup")
    end
    assert_includes error.message, "does not support grouped delivery"
    assert_nil RecordingStudioNotifications::Notification.find_by(idempotency_key: "fan-bad-rollup")

    refused = Object.new
    refused.define_singleton_method(:deliver) { |notification:, delivery:| }
    refused.define_singleton_method(:available_for?) { |recipient:, notification:, delivery:| false }
    RecordingStudioNotifications.channels.register(:fan_out_refused, refused)
    register_type(:fan_out_required_refused, channels: [:fan_out_refused], required: [:fan_out_refused])
    @fixed_recipients = [create_user("fan-refused")]
    run_fan_out(scope: :fan_out_fixed, notification_type: :fan_out_required_refused, idempotency_key: "fan-refused")
    assert_nil RecordingStudioNotifications::Notification.find_by(idempotency_key: "fan-refused")

    register_type(:fan_out_mismatch, scope: :optional_root)
    original = RecordingStudioNotifications::Services::RootResolver.method(:consistent?)
    RecordingStudioNotifications::Services::RootResolver.define_singleton_method(:consistent?) { |**| false }
    assert_raises(ArgumentError) do
      run_fan_out(prefix: "fan-more-checks", notification_type: :fan_out_mismatch, idempotency_key: "fan-mismatch")
    end
  ensure
    RecordingStudioNotifications::Services::RootResolver.define_singleton_method(:consistent?, original) if original
  end

  test "creation_action can allow the fan-out" do
    unless RecordingStudioAccessible.action_defined?(:fan_out_allow)
      RecordingStudioAccessible.define_action(:fan_out_allow) { true }
    end
    register_type(:fan_out_allowed, creation_action: :fan_out_allow)
    create_users("fan-allowed", 1)

    run_fan_out(prefix: "fan-allowed", notification_type: :fan_out_allowed, idempotency_key: "fan-allowed")

    assert_equal 1, RecordingStudioNotifications::Notification.where(idempotency_key: "fan-allowed").count
  end

  test "dummy scopes cover every user and page comment viewers" do
    create_users("fan-scope", 1)
    context = RecordingStudioNotifications::RecipientScopeRegistry::Context.new(actor: @actor)
    all_users = RecordingStudioNotifications.configuration.recipient_scopes.resolve(:all_users, context)
    assert_includes all_users, @actor
    assert_equal [], RecordingStudioNotifications.configuration.recipient_scopes.resolve(:page_comment_viewers, context)
  end

  private

  def create_user(prefix)
    User.create!(
      email: "#{prefix}-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  def create_users(prefix, count)
    self.class.email_prefix = prefix
    now = Time.current
    password = BCrypt::Password.create("Password123!").to_s
    User.insert_all(Array.new(count) do |index|
      {
        email: "#{prefix}-#{index}@example.test",
        encrypted_password: password,
        created_at: now,
        updated_at: now
      }
    end)
  end

  def register_type(key, channels: [:in_app], cadence: :individual, cadences: [cadence], scope: :global, required: [], creation_action: nil)
    RecordingStudioNotifications.notification_types.register(
      key,
      label: key.to_s.humanize,
      scope: scope,
      default_channels: channels,
      available_channels: (Array(channels) + Array(required)).uniq,
      required_channels: required,
      allowed_cadences: cadences,
      default_cadence: cadence,
      creation_action: creation_action
    )
  end

  def register_mail_adapter
    calls = []
    adapter = Object.new
    adapter.define_singleton_method(:deliver) { |notification:, delivery:| calls << delivery.id }
    adapter.define_singleton_method(:deliver_rollup) { |**| }
    RecordingStudioNotifications.channels.register(:fan_out_mail, adapter)
    calls
  end

  def run_fan_out(prefix: nil, scope: :fan_out_test_users, idempotency_key: "fan-out", **attributes)
    self.class.email_prefix = prefix if prefix
    payload = fan_out_payload(prefix: prefix, scope: scope, idempotency_key: idempotency_key, **attributes)
    clear_enqueued_jobs
    RecordingStudioNotifications::Services::FanOut.perform(payload)
  end

  def fan_out_payload(prefix: nil, scope: :fan_out_test_users, idempotency_key: "fan-out", notification_type: :fan_out_notice, **attributes)
    self.class.email_prefix = prefix if prefix
    job = RecordingStudioNotifications.notify_fan_out(
      recipient_scope: scope,
      notification_type: notification_type,
      actor: @actor,
      title: "Fan out",
      idempotency_key: idempotency_key,
      **attributes
    )
    job.arguments.first
  end

  def measure(prefix, count, key)
    create_users(prefix, count)
    payload = fan_out_payload(prefix: prefix, idempotency_key: key)
    clear_enqueued_jobs
    queries = ActiveRecord::Base.uncached { capture_queries { RecordingStudioNotifications::Services::FanOut.perform(payload) } }
    [queries.size, jobs_named("RecordingStudioNotifications::FanOutDeliveryJob")]
  end

  def capture_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA" || payload[:name] == "SCHEMA CACHE"
      next if sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      next if sql.include?("pg_") || sql.include?("information_schema")

      queries << sql
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def jobs_named(name)
    enqueued_jobs.count { |entry| job_name(entry) == name }
  end

  def job_name(entry)
    value = entry[:job] || entry["job"] || entry[:job_class] || entry["job_class"]
    value.is_a?(Class) ? value.name : value.to_s
  end

  def with_chunk_size(size)
    singleton = RecordingStudioNotifications::Services::FanOut.singleton_class
    original = RecordingStudioNotifications::Services::FanOut.method(:chunk_size)
    singleton.define_method(:chunk_size) { size }
    yield
  ensure
    singleton.define_method(:chunk_size, original)
  end

  def zoned_users
    User.define_method(:time_zone) do
      email.include?("tokyo") ? "Asia/Tokyo" : "Pacific/Honolulu"
    end
    [create_user("fan-tokyo"), create_user("fan-honolulu")]
  end

  def remove_time_zone
    return unless User.method_defined?(:time_zone) && User.instance_method(:time_zone).owner == User

    User.remove_method(:time_zone)
  end

  def define_denied_action
    return if RecordingStudioAccessible.action_defined?(:fan_out_deny)

    RecordingStudioAccessible.define_action(:fan_out_deny) { false }
  end
end
