# RecordingStudioNotifications

RecordingStudioNotifications is a Recording Studio addon Rails engine for root-aware, idempotent notifications.

## Features

- `RecordingStudioNotifications.notify` and `notify_each` public APIs
- Notification type registry and pluggable channel registry
- Bundled `:in_app` channel adapter
- UUID primary keys and UUID polymorphic recipient/actor/notifiable IDs
- Recording Studio root resolution from `root_recording`, `recording`, or a root recordable
- URL safety validation for relative paths and explicitly allowed hosts
- ActiveJob delivery jobs
- Accessible action registration for `:view_notifications`
- FlatPack/Tailwind engine views
- Install and migrations generators

No notification bell component/helper and no custom CSS are included.

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

## Configuration

```ruby
RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }
  config.allowed_url_hosts = ["example.com"]
  config.default_channels = [:in_app]

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    description: "A collaborator commented on a page.",
    default_channels: [:in_app]
  )
end
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
  idempotency_key: "comments/#{comment.id}/recipient/#{user.id}"
)
```

Send the same notification to many recipients:

```ruby
RecordingStudioNotifications.notify_each(
  recipients: users,
  notification_type: :workspace_digest,
  title: "Digest ready",
  url: "/"
)
```

## Channels

The bundled `:in_app` adapter records a delivery and marks it delivered. Register additional adapters with:

```ruby
RecordingStudioNotifications.register_channel(:email, MyEmailAdapter.new)
```

Adapters must respond to:

```ruby
deliver(notification:, delivery:)
```

Webhook delivery is intentionally left as a seam. This gem does not depend on CaptainHook/provider gems or send webhooks directly unless a host app registers an adapter backed by a public outgoing provider API.

## Authorization

The engine registers `:view_notifications` with RecordingStudioAccessible when available. The default policy allows actors to view their own notifications. Host apps can override the action policy:

```ruby
RecordingStudioAccessible.define_action(:view_notifications) do |actor:, recording:, context:, **|
  actor == context[:recipient] || RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :admin)
end
```

## Validation

Run from the repository root:

```bash
bundle exec rake test
```
