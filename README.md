# RecordingStudioNotifications

RecordingStudioNotifications is a Recording Studio addon Rails engine for root-aware, idempotent notifications.

## Features

- `RecordingStudioNotifications.notify` and `notify_each` public APIs
- Notification type registry with `default_channels`, `required_channels`, `available_channels`, `scope`, and optional `creation_action`
- Pluggable channel registry with bundled `:in_app` adapter
- UUID notifications, deliveries, and preferences tables
- Nullable `root_recording_id` for global/rootless notifications
- Current-root inbox behavior that includes global/rootless notifications
- Per-recipient settings for optional channels; required channels ignore preferences
- Accessible integration for root visibility, preference management, and optional creation authorization
- ActiveSupport instrumentation for notification creation and delivery
- FlatPack/Tailwind inbox and settings UI
- FlatPack notification menu integration with async hydration and configurable polling
- Install and migrations generators

Notifications are stored in their own engine tables and are not RecordingStudio recordings or recordables; Recording Studio events remain separate.

## Installation

Add the gem and install it in your host app:

```ruby
gem "recording_studio_notifications"
```

```bash
bin/rails generate recording_studio_notifications:install
bin/rails generate recording_studio_notifications:migrations
bin/rails db:migrate
```

Mount the engine in your app routes:

```ruby
mount RecordingStudioNotifications::Engine, at: "/notifications"
```

## Configuration

```ruby
RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }
  config.current_root_resolver = ->(controller:) { controller.send(:current_root_recording) }
  config.allowed_url_hosts = ["example.com"]
  config.default_channels = [:in_app]
  config.polling_interval_seconds = 60

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    description: "A collaborator commented on a page.",
    default_channels: [:in_app],
    required_channels: [],
    available_channels: [:in_app, :email],
    scope: :root,
    creation_action: :create_page_comment_notification
  )
end
```

Notification type scopes are:

- `:global` - always rootless.
- `:root` - requires a root recording.
- `:optional_root` - may be root-scoped or rootless/global.

The top-nav notification menu loads asynchronously after page render and then polls for updates on `config.polling_interval_seconds` (default: 60 seconds).

## Usage

```ruby
notification = RecordingStudioNotifications.notify(
  notification_type: :page_comment,
  recipient: user,
  actor: Current.actor,
  notifiable: page,
  title: "New comment",
  body: "A collaborator commented on your page.",
  url: "/pages/#{page.id}",
  idempotency_key: "comments/#{comment.id}/recipient/#{user.id}",
  deliver_later: true
)
```

Send the same notification to many recipients:

```ruby
RecordingStudioNotifications.notify_each(
  recipients: users,
  notification_type: :page_comment,
  title: "New page comment",
  url: "/"
)
```

## Channels and preferences

The bundled `:in_app` adapter uses the channel architecture and marks an in-app delivery as delivered. Register additional adapters with:

```ruby
RecordingStudioNotifications.register_channel(:email, MyEmailAdapter.new)
```

Adapters must respond to:

```ruby
deliver(notification:, delivery:)
```

Required channels are always delivered. Optional channels are delivered only when selected by the type/default request and not disabled by the recipient's preference.

Webhook delivery is intentionally deferred: host apps may register a custom adapter backed by CaptainHook or another approved outgoing provider API.

## Authorization

The engine registers Accessible actions for viewing notifications and managing preferences when `RecordingStudioAccessible` is available. Root-scoped inbox visibility checks Accessible `:view` on the root recording. Preference pages use `:"recording_studio_notifications.manage_preferences"`. Types with `creation_action:` require that Accessible action before creation.

## UI

The engine provides:

- `/notifications` inbox (current-root view, including global/rootless notifications)
- `/notifications/menu.json` async top-nav menu payload (unread count + recent notifications)
- `/settings` notification channel preferences

Both views use FlatPack components and Tailwind utility classes only.

## Instrumentation

Subscribe to:

- `notify.recording_studio_notifications`
- `deliver.recording_studio_notifications`

## Validation

Run from the repository root:

```bash
bundle exec rake test
```
