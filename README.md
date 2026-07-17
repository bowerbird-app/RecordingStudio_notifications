# RecordingStudioNotifications

RecordingStudioNotifications is a mountable Rails engine for root-aware, idempotent notifications in Recording Studio applications. Notifications use the engine's own tables; they are not Recording Studio recordings or recordables, and Recording Studio events remain separate.

## Features

- `RecordingStudioNotifications.notify` and `notify_each` public APIs
- UUID notifications, deliveries, and per-recipient preferences
- Idempotent creation with a recipient-scoped `idempotency_key`
- Global, root-scoped, and optional-root notification types
- A pluggable channel registry with a bundled `:in_app` adapter
- Required and optional delivery channels, controlled by recipient preferences
- Optional per-type delivery cadences and grouped rollup delivery
- FlatPack/Tailwind inbox, notification menu, and preference UI
- Engine-owned Stimulus polling controller for the async notification menu
- Recording Studio Accessible authorization, ActiveSupport instrumentation, hooks, and install/migration generators

## Requirements

- Ruby 3.3 or newer
- Rails 8.1
- `recording_studio`, `recording_studio_accessible`, `flat_pack`, and `view_component`
- A host application with a current actor resolver; the bundled UI also expects FlatPack and Stimulus

## Installation

Add the gem to the host application's `Gemfile`:

```ruby
gem "recording_studio_notifications"
```

Install the engine, copy migrations, and migrate:

```bash
bundle install
bin/rails generate recording_studio_notifications:install
bin/rails generate recording_studio_notifications:migrations
bin/rails db:migrate
```

The installer mounts the engine at `/recording_studio_notifications` by default. Choose a different mount path when invoking it:

```bash
bin/rails generate recording_studio_notifications:install --mount-path=/notifications
```

The installer also adds Tailwind source paths when it finds `app/assets/tailwind/application.css`, and adds the engine's polling controller to a standard Stimulus controller loader. Review the generated `config/initializers/recording_studio_notifications.rb`, register the notification types your app emits, and configure its actor/root resolvers.

## Configuration

Configuration can be set in the generated initializer, `config/recording_studio_notifications.yml`, or `Rails.application.config.x.recording_studio_notifications`.

```ruby
RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }
  config.current_root_resolver = ->(controller:) { controller.send(:current_root_recording) }
  config.allowed_url_hosts = ["example.com"]
  config.default_channels = [:in_app]
  config.deliver_later = true
  config.queue_name = :default
  config.raise_on_delivery_error = false
  config.polling_interval_seconds = 60

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    category: :collaboration,
    description: "A collaborator commented on a page.",
    icon: :chat_bubble_left_ellipsis,
    default_channels: [:in_app],
    required_channels: [],
    available_channels: [:in_app, :email],
    scope: :root,
    creation_action: :create_page_comment_notification
  )
end
```

The engine registers a default `:generic` type with `:in_app` delivery. `allowed_url_hosts` controls absolute HTTP(S) notification URLs; relative paths are always accepted.

### Notification types

Each type has a `label`, optional `description`, `category`, Heroicons v2 `icon`, channels, scope, and optional `creation_action`. Valid scopes are:

- `:global`: always rootless.
- `:root`: requires a root recording.
- `:optional_root`: may be root-scoped or rootless.

Types can also offer delivery cadences. Valid values are `:individual`, `:daily`, `:every_other_day`, `:weekly`, `:biweekly`, and `:monthly`.

```ruby
config.notification_types.register(
  :weekly_digest,
  label: "Weekly digest",
  default_channels: [:in_app, :email],
  available_channels: [:in_app, :email],
  allowed_cadences: [:individual, :daily, :weekly],
  default_cadence: :weekly,
  scope: :optional_root
)
```

Cadence preferences and rollup delivery are disabled by default. Enable them only after registering rollup-capable external channel adapters:

```ruby
config.rollup_delivery_enabled = true
config.rollup_reservation_timeout = 15.minutes
```

## Creating notifications

```ruby
notification = RecordingStudioNotifications.notify(
  notification_type: :page_comment,
  recipient: user,
  actor: Current.actor,
  notifiable: page,
  root_recording: current_root_recording,
  title: "New comment",
  body: "A collaborator commented on your page.",
  url: "/pages/#{page.id}",
  metadata: { comment_id: comment.id },
  idempotency_key: "comments/#{comment.id}/recipient/#{user.id}",
  deliver_later: true
)
```

`recipient`, `notification_type`, and `title` are required. The notification type determines whether a root recording is required. `actor` defaults to `config.actor_resolver`; a root can also be derived from `recording:` or `notifiable:` when they belong to a Recording Studio root.

Send the same payload to several recipients with `notify_each`:

```ruby
RecordingStudioNotifications.notify_each(
  recipients: users,
  notification_type: :page_comment,
  title: "New page comment",
  url: "/"
)
```

Pass `channels:` to request a subset of a type's available channels. Required channels are always included. Optional channels respect each recipient's preference.

## Host UI integration

The engine supplies an inbox, preferences screen, and async top-nav notification menu. Add the menu helper to a host layout:

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  include RecordingStudioNotifications::MenuHelper
end
```

```erb
<%= recording_studio_notifications_async_menu(recipient: current_user, limit: 5) %>
```

The helper renders FlatPack's `Notification::Component`, fetches the menu payload after page load, and polls at `config.polling_interval_seconds` (60 seconds by default). It returns nothing for a blank recipient.

The polling controller is shipped by the engine as `recording-studio-notifications--notification-polling`. The installer adds this to a standard `app/javascript/controllers/index.js`; apps with a custom controller loader must add:

```javascript
lazyLoadControllersFrom("controllers/recording_studio_notifications", application)
```

The host layout must include its normal `javascript_importmap_tags` and a Stimulus application. The engine registers its importmap pins and JavaScript asset path automatically.

## Channels, preferences, and delivery

The bundled `:in_app` adapter marks deliveries as delivered. Register an external adapter with:

```ruby
RecordingStudioNotifications.register_channel(:email, MyEmailAdapter.new)
```

Every adapter must implement:

```ruby
deliver(notification:, delivery:)
```

When `rollup_delivery_enabled` is true, adapters used with a non-individual cadence must additionally implement:

```ruby
deliver_rollup(
  notifications:, deliveries:, rollup_key:, cadence:,
  period_starts_at:, period_ends_at:, idempotency_key:
)
```

The preferences screen exposes optional channels and, when rollups are enabled, selectable type cadences. Required channels cannot be disabled. Schedule closed rollups with:

```bash
bin/rails recording_studio_notifications:deliver_rollups
```

Delivery failures mark the delivery failed. Set `config.raise_on_delivery_error = true` when your job backend should retry by raising the original error.

## Routes and authorization

All paths below are relative to the engine mount point:

- `/` and `/notifications`: current-root inbox, including global/rootless notifications
- `/notifications/menu.json`: async notification-menu payload
- `/notifications/:id/open`: marks a notification read and redirects to its URL
- `/notifications/:id/mark_read`, `/mark_unread`, `/archive`, and `/unarchive`: inbox actions
- `/notifications/clear_all`: clears visible unread notifications
- `/settings`: notification channel and cadence preferences

The engine resolves the current recipient from `current_user`, when available, then `config.actor_resolver`. It registers Accessible actions for viewing notifications and managing preferences when `RecordingStudioAccessible` is present. Root-scoped visibility checks Accessible `:view` against the root recording. A type's `creation_action:` is checked before it can be emitted.

## Hooks and instrumentation

Hosts can register lifecycle hooks through `RecordingStudioNotifications.configuration.hooks`:

```ruby
RecordingStudioNotifications.configuration.hooks.after_service do |service_class, notification|
  Rails.logger.info("Created #{notification.id} via #{service_class.name}")
end
```

Available lifecycle/service hooks include `before_initialize`, `on_configuration`, `after_initialize`, `before_service`, `around_service`, and `after_service`. Model and controller extensions can be registered with `extend_model` and `extend_controller`.

Subscribe to these ActiveSupport notifications:

- `notify.recording_studio_notifications`
- `deliver.recording_studio_notifications`
- `deliver_rollup.recording_studio_notifications`

## Validation

Run the engine suite from the repository root:

```bash
bundle exec rake test
```
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

To add the menu to a host layout, include the engine helper and render it for the signed-in recipient:

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  include RecordingStudioNotifications::MenuHelper
end
```

```erb
<%= recording_studio_notifications_async_menu(recipient: current_user, limit: 5) %>
```

The engine ships the `recording-studio-notifications--notification-polling` Stimulus controller. The install generator adds it to a standard controller loader; custom loaders must include:

```javascript
lazyLoadControllersFrom("controllers/recording_studio_notifications", application)
```

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
