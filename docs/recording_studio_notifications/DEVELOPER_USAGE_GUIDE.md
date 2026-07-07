# RecordingStudioNotifications Developer Usage Guide

This guide is a practical, end-to-end walkthrough for host app developers using the `recording_studio_notifications` gem.

It covers:

- Installation and engine mount
- Notification type registration
- Recording Studio root and recordable setup considerations
- How to create notifications safely
- How to mark notifications read/unread/archive
- How channel preferences work
- Authorization behavior
- Jobs, delivery adapters, and instrumentation
- Troubleshooting and implementation patterns

## 1. What This Gem Does

`RecordingStudioNotifications` is a mountable Rails engine that stores and delivers notifications in a root-aware, idempotent way.

Important design points:

- Notifications are stored in the engine tables, not as Recording Studio recordings.
- You can still attach a notification to Recording Studio context using `recording` and `root_recording`.
- Root-aware inbox filtering supports both all notifications and current-root view.
- Notification creation is idempotent via `idempotency_key`.
- Delivery is channel-based, with built-in `:in_app` and support for custom channels.

## 2. Install In A Host App

Add the gem:

```ruby
# Gemfile
gem "recording_studio_notifications"
```

Install and migrate:

```bash
bin/rails generate recording_studio_notifications:install
bin/rails generate recording_studio_notifications:migrations
bin/rails db:migrate
```

The install generator mounts the engine (default mount path is `/recording_studio_notifications`).

You can mount manually too:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RecordingStudioNotifications::Engine, at: "/notifications"
end
```

Once mounted, engine-internal routes include:

- `GET /notifications` (index)
- `GET /notifications/:id` (show)
- `GET /notifications/:id/open` (mark read + redirect)
- `PATCH /notifications/:id/mark_read`
- `PATCH /notifications/:id/mark_unread`
- `PATCH /notifications/:id/archive`
- `GET /settings`
- `PATCH /settings`

Note: the final full URL depends on your mount path.

## 3. Configure The Engine

The install generator creates an initializer. A practical starting point:

```ruby
# config/initializers/recording_studio_notifications.rb
RecordingStudioNotifications.configure do |config|
  # Resolve current actor for service calls and controller authorization fallback.
  config.actor_resolver = -> { Current.actor if defined?(Current) }

  # Resolve currently selected root recording for inbox scope=current_root.
  config.current_root_resolver = ->(controller:) do
    controller.send(:current_root_recording) if controller.respond_to?(:current_root_recording, true)
  end

  # Relative URLs are always allowed. Add hosts if you use absolute URLs.
  config.allowed_url_hosts = [Rails.application.routes.default_url_options[:host]].compact

  # Delivery defaults.
  config.default_channels = [:in_app]
  config.deliver_later = true
  config.queue_name = :default
  config.raise_on_delivery_error = false
end
```

## 4. Register Notification Types (Registration)

Before you call `notify`, register the notification type. This is the key contract that defines scope and channel behavior.

```ruby
# config/initializers/recording_studio_notifications.rb
RecordingStudioNotifications.configure do |config|
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

Scope options:

- `:global` means rootless only (`root_recording` must be blank).
- `:root` means root required.
- `:optional_root` means either root-scoped or rootless.

Channel options:

- `required_channels`: always delivered, cannot be disabled by preferences.
- `available_channels`: total channel set for that type.
- `default_channels`: initial optional channel selection when none is explicitly passed.

## 5. Recording Studio / Recordable Setup (What Is Required?)

Short answer:

- This gem does not require you to make notifications themselves recordables.
- You only need Recording Studio context if your notification type or UX needs root-scoped behavior.

How context is derived:

- You may pass `root_recording` directly.
- Or pass `recording` and let root be resolved.
- Or pass `notifiable` (recordable model) and let root be resolved.
- For `:root` types, a root must be resolvable or an error is raised.

For root consistency, the gem validates that these references do not conflict.

Example using all contextual references:

```ruby
RecordingStudioNotifications.notify(
  notification_type: :page_comment,
  recipient: user,
  actor: Current.actor,
  notifiable: page,
  recording: page_recording,
  root_recording: workspace_root,
  title: "New comment",
  body: "A collaborator commented on your page.",
  url: "/pages/#{page.id}",
  idempotency_key: "comment-#{comment.id}-user-#{user.id}"
)
```

If your app does not use root scoping for a given type, prefer `scope: :global` or `scope: :optional_root` and omit root fields.

## 6. Create Notifications (Single Recipient)

### Minimal call

```ruby
RecordingStudioNotifications.notify(
  notification_type: :generic,
  recipient: user,
  title: "Welcome",
  body: "Thanks for joining"
)
```

### Production-grade call

```ruby
notification = RecordingStudioNotifications.notify(
  notification_type: :page_comment,
  recipient: recipient,
  actor: Current.actor,
  notifiable: page,
  recording: page_recording,
  root_recording: page_recording.root_recording,
  title: "New comment on #{page.title}",
  body: comment.body.to_s.truncate(200),
  url: Rails.application.routes.url_helpers.page_path(page),
  metadata: {
    comment_id: comment.id,
    page_id: page.id,
    workspace_id: page_recording.root_recording&.id
  },
  channels: [:in_app],
  idempotency_key: "comment-#{comment.id}-recipient-#{recipient.id}",
  deliver_later: true
)
```

### Arguments reference

- `notification_type:` required, must be registered
- `recipient:` required
- `title:` required
- `body:` optional
- `url:` optional, sanitized for safety
- `metadata:` optional JSON-like hash
- `actor:` optional, falls back to configured resolver
- `notifiable:` optional polymorphic association
- `recording:` optional Recording Studio recording context
- `root_recording:` optional unless type scope requires it
- `channels:` optional requested channels
- `idempotency_key:` optional but strongly recommended for event-driven notifications
- `deliver_later:` optional per-call override

## 7. Create Notifications For Multiple Recipients

Use `notify_each` for fan-out:

```ruby
notifications = RecordingStudioNotifications.notify_each(
  recipients: viewers,
  notification_type: :page_comment,
  actor: Current.actor,
  notifiable: page,
  recording: page_recording,
  root_recording: page_recording.root_recording,
  title: "New comment on #{page.title}",
  body: comment.body.to_s.truncate(200),
  url: Rails.application.routes.url_helpers.page_path(page)
)
```

For strict dedupe across retries, call `notify` per recipient with an explicit `idempotency_key` that includes recipient id.

## 8. Trigger Notifications From Domain Events

Recommended pattern: trigger from a successful service/hook outcome, not directly in controllers.

```ruby
# Example pattern inside a hook or service callback
workspace_viewers.each do |viewer|
  RecordingStudioNotifications.notify(
    notification_type: :page_comment,
    recipient: viewer,
    actor: comment.author,
    recording: comment_recording,
    root_recording: comment_recording.root_recording,
    title: "New comment on #{page.title}",
    body: comment.body.to_s.truncate(200),
    url: Rails.application.routes.url_helpers.page_path(page),
    idempotency_key: "comment-#{comment.id}-viewer-#{viewer.id}"
  )
end
```

Benefits:

- Notifications only fire when the domain event truly succeeded.
- Clear retry semantics.
- Easier idempotency strategy.

## 9. Mark Notification As Read / Unread / Archive

### Via engine routes (recommended UI flow)

```erb
<%= link_to "Open", open_notification_path(notification), data: { turbo_method: :get } %>

<%= button_to "Mark read",
              mark_read_notification_path(notification),
              method: :patch %>

<%= button_to "Mark unread",
              mark_unread_notification_path(notification),
              method: :patch %>

<%= button_to "Archive",
              archive_notification_path(notification),
              method: :patch %>
```

Behavior:

- `open` marks unread notifications as read, then redirects to notification URL (or show page fallback).
- `mark_read` sets `read_at` once.
- `mark_unread` clears `read_at`.
- `archive` sets `archived_at` and removes from active list.

### Via model methods (service/admin use)

```ruby
notification.mark_read!
notification.mark_unread!
notification.archive!
notification.unarchive!
```

Scopes you can use in your own queries:

```ruby
RecordingStudioNotifications::Notification.for_recipient(user).unread
RecordingStudioNotifications::Notification.for_recipient(user).active
RecordingStudioNotifications::Notification.for_recipient(user).archived
```

## 10. Current-Root Inbox Filtering

The index supports two inbox scopes:

- `all`
- `current_root`

Example links:

```erb
<%= link_to "All", notifications_path(inbox_scope: "all") %>
<%= link_to "Current root", notifications_path(inbox_scope: "current_root") %>
```

When `current_root` is active:

- notifications for current root are included
- rootless/global notifications are also included

## 11. Channel Preferences

Users can manage optional channel preferences per notification type in settings.

Routes:

- `GET settings_path`
- `PATCH settings_path`

Preference model API:

```ruby
RecordingStudioNotifications::Preference.set!(
  recipient: user,
  notification_type: :page_comment,
  channel: :email,
  enabled: false
)

enabled = RecordingStudioNotifications::Preference.enabled_for?(
  recipient: user,
  notification_type: :page_comment,
  channel: :email,
  default: true
)
```

Delivery selection rules:

- required channels always send
- optional channels send only if selected and not disabled by preference

## 12. Add A Custom Channel Adapter

Register an adapter that responds to `deliver(notification:, delivery:)`.

```ruby
class EmailNotificationAdapter
  def deliver(notification:, delivery:)
    NotificationMailer.with(notification: notification).deliver_now
    delivery.mark_delivered!
  rescue StandardError
    delivery.mark_failed!
    raise
  end
end

RecordingStudioNotifications.register_channel(:email, EmailNotificationAdapter.new)
```

Then include `:email` in notification type `available_channels` (and optionally defaults).

## 13. Authorization Model

Three common checks exist:

- viewing notifications
- managing preferences
- optional creation authorization per notification type (`creation_action`)

If `RecordingStudioAccessible` is present, authorization uses its action checks.

Without it, a safe fallback allows same actor == recipient access.

For root-scoped visibility, a notification can still be hidden if actor lacks view rights on that root.

## 14. Background Jobs And Delivery Pipeline

Create flow:

1. validate input and authorization
2. create/find notification (idempotency)
3. create pending deliveries
4. enqueue `DeliveryJob` (or perform inline)

`DeliveryJob` loads pending deliveries and dispatches each to the registered adapter for that channel.

Important config options:

- `deliver_later` global default
- `queue_name` from `ApplicationJob`
- `raise_on_delivery_error` controls whether adapter errors bubble

## 15. Instrumentation Hooks

Subscribe to these events:

- `notify.recording_studio_notifications`
- `deliver.recording_studio_notifications`

Example subscriber:

```ruby
ActiveSupport::Notifications.subscribe("notify.recording_studio_notifications") do |_name, start, finish, _id, payload|
  Rails.logger.info(
    "notification_created type=#{payload[:notification_type]} recipient=#{payload[:recipient].class}-#{payload[:recipient].id} duration_ms=#{((finish - start) * 1000).round}"
  )
end
```

## 16. Error Cases You Should Expect

Common `ArgumentError` causes:

- missing recipient
- blank title
- unregistered notification type
- required root not present for `:root` types
- unregistered or unavailable channel
- unsafe URL
- inconsistent root/recording/notifiable scope

Recommended handling pattern:

```ruby
begin
  RecordingStudioNotifications.notify(...)
rescue ArgumentError => e
  Rails.logger.warn("Notification skipped: #{e.message}")
end
```

## 17. Practical Implementation Checklist

1. Install gem, run install and migration generators, migrate.
2. Register all notification types in initializer.
3. Decide scope (`:global`, `:root`, `:optional_root`) per type.
4. Add event-driven notify calls with stable idempotency keys.
5. Ensure actor/root resolvers match your host app.
6. Wire UI actions to open/read/unread/archive routes.
7. Add optional channels and preferences only when you have adapters.
8. Add instrumentation subscribers for operational visibility.

## 18. Example: Full End-To-End Page Comment Flow

```ruby
# config/initializers/recording_studio_notifications.rb
RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.user }

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    description: "Someone commented on a page you can access",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :root
  )
end
```

```ruby
# app/services/comments/create_and_notify.rb
class Comments::CreateAndNotify
  def self.call(page:, author:, body:)
    comment = page.comments.create!(author: author, body: body)

    page_recording = RecordingStudio::Recording.find_by!(recordable: page)
    root = page_recording.root_recording

    recipients = WorkspaceMembers.for_root(root).where.not(id: author.id)

    recipients.find_each do |recipient|
      RecordingStudioNotifications.notify(
        notification_type: :page_comment,
        recipient: recipient,
        actor: author,
        notifiable: page,
        recording: page_recording,
        root_recording: root,
        title: "New comment on #{page.title}",
        body: body.to_s.truncate(200),
        url: Rails.application.routes.url_helpers.page_path(page),
        idempotency_key: "comment-#{comment.id}-recipient-#{recipient.id}"
      )
    end

    comment
  end
end
```

```erb
<!-- app/views/notifications/_item.html.erb -->
<%= link_to "Open", open_notification_path(notification) %>
<%= button_to "Mark read", mark_read_notification_path(notification), method: :patch %>
<%= button_to "Mark unread", mark_unread_notification_path(notification), method: :patch %>
<%= button_to "Archive", archive_notification_path(notification), method: :patch %>
```

This pattern gives you:

- dedupe-safe notification creation
- root-aware visibility
- standard read/unread/archive controls
- channel-delivery extensibility later

## 19. Final Notes

If you are just getting started, begin with:

- one type (`:generic` or one business type)
- one channel (`:in_app`)
- one event-driven creation path
- explicit idempotency key

Then incrementally add:

- additional types
- optional channels and preferences
- stricter creation authorization (`creation_action`)
- richer instrumentation and dashboards
