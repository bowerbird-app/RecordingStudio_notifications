> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/recording_studio_notifications](https://github.com/bowerbird-app/recording_studio_notifications/tree/main/docs/recording_studio_notifications)
> *   **Last Updated:** July 13, 2026
>
> *Maintainers: Update the date above when modifying this file.*

---

# RecordingStudioNotifications Configuration

This document describes the real, current configuration surface for RecordingStudioNotifications.

---

## Quick Start

Run the install generator:

```bash
rails generate recording_studio_notifications:install
```

This does the following:

1. Mounts the engine in routes (`/recording_studio_notifications` by default).
2. Creates `config/initializers/recording_studio_notifications.rb`.
3. Optionally creates `config/recording_studio_notifications.yml` for environment overrides.

---

## Configuration Options

| Option | Type | Default | Description |
|---|---|---|---|
| `actor_resolver` | Proc | resolves `Current.actor` when available | Resolves the acting user when `actor:` is omitted from `notify`. |
| `current_root_resolver` | Proc | controller-based root resolver | Resolves the active root recording used by inbox visibility/scoping logic. |
| `allowed_url_hosts` | Array | `[]` | Allowlist for absolute notification URLs. Relative paths are always allowed. |
| `default_channels` | Array | `[:in_app]` | Default channels for type registration and delivery fallback. |
| `deliver_later` | Boolean | `true` | Whether deliveries enqueue via ActiveJob by default. |
| `queue_name` | Symbol/String | `:default` | Queue used by notification delivery jobs. |
| `raise_on_delivery_error` | Boolean | `false` | If true, delivery exceptions bubble; if false, errors are captured/logged. |
| `polling_interval_seconds` | Integer | `60` | Polling cadence for async notification menu refresh. |
| `rollup_reservation_timeout` | ActiveSupport duration | `15.minutes` | Releases an interrupted rollup reservation for a later scheduler retry. |
| `rollup_delivery_enabled` | Boolean | `false` | Enables scheduled external rollup dispatch after channel adapters and scheduler are ready. |

---

## Ruby Initializer (Recommended)

```ruby
RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }
  config.current_root_resolver = ->(controller:) do
    controller.send(:current_root_recording) if controller.respond_to?(:current_root_recording, true)
  end

  config.allowed_url_hosts = [Rails.application.routes.default_url_options[:host]].compact
  config.default_channels = [:in_app]
  config.deliver_later = true
  config.queue_name = :default
  config.raise_on_delivery_error = false

  # Top-nav menu polling interval (seconds)
  config.polling_interval_seconds = 60

  # Enable only after configuring a recurring scheduler and rollup-capable adapters.
  config.rollup_delivery_enabled = false
end
```

---

## YAML and config.x Overrides

The engine supports the same keys from:

1. `config/recording_studio_notifications.yml` via `config_for`
2. `config.x.recording_studio_notifications`
3. Initializer block overrides

Example YAML:

```yaml
development:
  polling_interval_seconds: 30
  deliver_later: true
  queue_name: default

production:
  polling_interval_seconds: 60
  deliver_later: true
  queue_name: notifications
```

Example `config.x`:

```ruby
config.x.recording_studio_notifications.polling_interval_seconds = 45
config.x.recording_studio_notifications.deliver_later = true
```

---

## Notification Type Registration

Register types in the initializer with `config.notification_types.register(...)`.

```ruby
RecordingStudioNotifications.configure do |config|
  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    category: :page,
    description: "Optional-root notification for comments on pages.",
    icon: :chat_bubble_left_ellipsis,
    default_channels: [:in_app],
    available_channels: [:in_app],
    allowed_cadences: %i[individual daily weekly monthly],
    default_cadence: :weekly,
    required_cadence: nil,
    scope: :optional_root
  )
end
```

### Notification Cadence Rules

Notification cadence controls when enabled channels deliver notifications and how source notifications are grouped in the in-app inbox.

- `allowed_cadences` lists the recipient-selectable values. Supported values are `:individual`, `:daily`, `:every_other_day`, `:weekly`, `:biweekly`, and `:monthly`.
- `default_cadence` applies when no recipient-specific override exists.
- `required_cadence` forces one value and disables recipient selection when preference support is enabled.
- Omitting all cadence options preserves immediate behavior with `allowed_cadences: [:individual]` and `default_cadence: :individual`.

The registry rejects an empty allowed-cadence list and requires both the default and required cadence, when present, to be included in `allowed_cadences`.

### Cadence Preference Storage

Recipient-specific cadence overrides share the notification preferences table with channel preferences, but use a distinct row shape:

| Preference | `channel` | `enabled` | `cadence` |
| --- | --- | --- | --- |
| Channel setting | Channel name | Boolean | `NULL` |
| Cadence override | `NULL` | `NULL` | Cadence name |

Use the separate APIs to keep these concerns isolated:

```ruby
RecordingStudioNotifications::Preference.set!(
  recipient: user,
  notification_type: :page_comment,
  channel: :email,
  enabled: true
)

RecordingStudioNotifications::Preference.set_cadence!(
  recipient: user,
  notification_type: :page_comment,
  cadence: :daily
)

RecordingStudioNotifications::Preference.cadence_for(
  recipient: user,
  notification_type: :page_comment,
  default: :weekly
)
```

Saving a type's default cadence deletes its recipient override. Reading cadence never creates a preference row. Required cadence values take precedence over stored overrides.

### Notification Cadence Settings

The settings page keeps channel preferences and notification cadence separate:

- A **Notification cadence** selector appears when a type permits more than one cadence and does not require one.
- Selecting the default cadence removes the recipient override; selecting another allowed value saves an override.
- Types with `required_cadence` show a non-editable explanation instead of a selector.
- Channel selections and cadence submissions are independent, so updating cadence does not change channel preferences.

Selector help text explains the combined effect: it controls when the type is delivered through enabled channels and how its source notifications are grouped in the inbox.

### Inbox Grouping

Active, authorized notifications are grouped in the inbox using the recipient's effective cadence and time zone. The recipient time zone is used when available; otherwise the application time zone is used.

- `:individual` notifications remain separate rows.
- `:daily`, `:every_other_day`, `:weekly`, `:biweekly`, and `:monthly` notifications render as collapsible type sections.
- Weeks start on Monday. Two-day and biweekly periods use stable fixed anchors.
- The newest group in each type section starts expanded, and pagination preserves whole groups.
- The compact notification menu uses the same grouping data, ordered by each group's newest source notification.

Grouping is display-only. Source notifications retain their independent read and archive state.

The inbox supports marking all unread source notifications in a visible group as read. The bulk action re-resolves the group from the recipient's active, authorized notifications in the current inbox scope before updating rows. Expanding or collapsing a group never changes notification state, and the global unread badge remains a count of unread source notifications.

### Cadence-Aware Delivery

`individual` cadence preserves the existing delivery pipeline: each source notification is sent through each enabled channel immediately.

For grouped cadences, the engine still creates one source notification and one delivery audit row per enabled channel. Grouped external-channel rows remain pending for the Phase 6 rollup scheduler and include deterministic metadata:

- `rollup: true`
- `rollup_key`
- `cadence`
- `period_starts_at`
- `period_ends_at`

The rollup key combines recipient, notification type, channel, effective cadence, and period start. The immediate delivery job skips these deferred rows. In-app rows remain immediate because the source notifications are already available in their inbox group.

### Rollup Scheduler

Run this task from the host application's recurring scheduler, such as cron, Solid Queue recurring tasks, or the deployment platform scheduler:

```bash
bundle exec rake recording_studio_notifications:deliver_rollups
```

The task delivers only closed periods when `rollup_delivery_enabled` is true. It transactionally reserves all rows with one `rollup_key`, calls the channel adapter once through `deliver_rollup`, and passes that key as `idempotency_key`. Failed rows remain retryable on later runs, while reservations older than `rollup_reservation_timeout` are released for crash recovery. Grouped external notification creation requires an adapter that implements `deliver_rollup`; otherwise the engine raises before source and delivery records are created.

A grouped external adapter must implement both the existing immediate-delivery method and a rollup method:

```ruby
def deliver(notification:, delivery:)
  # Individual cadence delivery.
end

def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:, idempotency_key:)
  # Send one channel-specific rollup. Use idempotency_key with the provider when supported.
end
```

### Rollout Checklist

1. Deploy migrations and leave `rollup_delivery_enabled` disabled; existing types remain immediate unless configured otherwise.
2. Configure allowed/default cadence values, verify inbox grouping, and enable recipient cadence selection.
3. Implement and validate `deliver_rollup` for every external channel that will allow grouped cadence.
4. Configure a recurring host scheduler for `recording_studio_notifications:deliver_rollups`.
5. Enable `rollup_delivery_enabled` and monitor failed deliveries, reservation recovery, and provider idempotency behavior.

### Scope Rules

- `:global` must be rootless.
- `:root` requires `root_recording`.
- `:optional_root` supports both root-scoped and rootless notifications.

### Icon Rules

- Icons use Heroicons v2 symbol names.
- Omitted `icon:` defaults to `:bell`.
- Menu/inbox UI uses the registered icon per notification type.

---

## Notification Menu Polling

The top-nav notification menu is hydrated asynchronously after page load and then polled.

- Endpoint: `/notifications/menu.json` (under your mount path)
- Payload includes unread count, recent items, and rendered menu HTML.
- Poll interval is controlled by `polling_interval_seconds`.
- Non-positive values are normalized to `60` seconds.

---

## Load Order and Precedence

Configuration merge order (later wins):

1. Defaults in `RecordingStudioNotifications::Configuration`
2. `config/recording_studio_notifications.yml`
3. `config.x.recording_studio_notifications`
4. Initializer (`RecordingStudioNotifications.configure`)

---

## Runtime Access

```ruby
RecordingStudioNotifications.configuration.polling_interval_seconds
RecordingStudioNotifications.configuration.deliver_later
RecordingStudioNotifications.configuration.to_h
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| YAML values not applying | Ensure `config/recording_studio_notifications.yml` has valid YAML and environment keys. |
| `config.x` ignored | Verify keys are set in the active environment file. |
| Polling too frequent/slow | Set `polling_interval_seconds` to a suitable positive integer in initializer/YAML/config.x. |

---

## File Reference

- `lib/recording_studio_notifications/configuration.rb`
- `lib/recording_studio_notifications/engine.rb`
- `lib/generators/recording_studio_notifications/install/templates/recording_studio_notifications_initializer.rb`

---

Happy configuring.
