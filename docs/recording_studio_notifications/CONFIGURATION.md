> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/recording_studio_notifications](https://github.com/bowerbird-app/recording_studio_notifications/tree/main/docs/recording_studio_notifications)
> *   **Last Updated:** July 9, 2026
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
    scope: :optional_root
  )
end
```

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
