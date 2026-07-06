# Notification Types, Hooks, and End-to-End Flow

This guide explains how notifications work in this repository, using the Page comment example implemented in the dummy app.

Audience:
- Junior developers who need practical implementation steps
- Project managers who want to understand the business flow without deep Rails knowledge

## 1) High-level flow (plain language)

When someone posts a comment on a Page:
1. The app creates the comment.
2. A hook runs after comment creation succeeds.
3. The hook decides who should be notified (workspace members with view access, excluding the commenter).
4. The hook creates one notification per recipient.
5. Notification deliveries are queued via ActiveJob.
6. For in-app channel, delivery marks as delivered.
7. User clicks a notification, it is marked as read, then user is redirected to the target URL.

## 2) Where notification types are registered

In the dummy app, notification types are configured in:
- test/dummy/config/initializers/recording_studio_notifications.rb

Code excerpt:

```ruby
RecordingStudioNotifications.configure do |config|
  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    description: "Optional-root notification for comments on pages.",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :optional_root
  )
end
```

What this means:
- :page_comment is the internal key used when creating notifications.
- label/description are metadata for humans/admin UI.
- default_channels: [:in_app] means in-app bell/inbox is used by default.
- available_channels: [:in_app] means only in-app is currently enabled.
- scope: :optional_root means notification can be tied to a workspace root, but can also be rootless.

Scope options supported by the engine:
- :global: must not have a root recording
- :root: must have a root recording
- :optional_root: either is allowed

## 3) How comment creation triggers notifications via hook

The hook is in:
- test/dummy/config/initializers/recording_studio_commentable.rb

Code excerpt:

```ruby
RecordingStudioCommentable.configuration.hooks.after_service(priority: 10) do |service_class, result|
  next unless service_class == RecordingStudioCommentable::Services::CreateComment
  next unless result.success?

  comment = result.value
  comment_recording = RecordingStudio::Recording.find_by(recordable: comment)
  next unless comment_recording

  parent_recording = comment_recording.parent_recording
  next unless parent_recording

  page_recordable = parent_recording.recordable
  next unless page_recordable.is_a?(Page)

  root_recording = comment_recording.root_recording
  next unless root_recording

  workspace_viewers = RecordingStudio::Recording.unscoped
    .where(
      parent_recording_id: root_recording.id,
      recordable_type: "RecordingStudio::Access",
      trashed_at: nil
    )
    .map { |r| r.recordable&.actor }
    .compact
    .reject { |actor| actor == comment.author }

  next if workspace_viewers.empty?

  url = Rails.application.routes.url_helpers.page_path(page_recordable)
  workspace_viewers.each do |viewer|
    RecordingStudioNotifications.notify(
      notification_type: :page_comment,
      recipient: viewer,
      actor: comment.author,
      recording: comment_recording,
      root_recording: root_recording,
      title: "New comment on #{page_recordable.title}",
      body: comment.body.to_s.truncate(200),
      url: url,
      idempotency_key: "comment-#{comment.id}-#{viewer.id}"
    )
  end
end
```

What this code does:
- Runs only for successful comment creation service calls.
- Ensures the comment belongs to a Page.
- Extracts the root recording of that comment's workspace.
- Finds users with workspace access under that root.
- Excludes the author (no self-notification).
- Creates one notification per recipient.
- Uses idempotency_key to avoid duplicate rows for the same comment+recipient pair.

## 4) Which root is notified

For Page comments, the notified root is:
- comment_recording.root_recording

Why this root:
- It guarantees notifications are tied to the same workspace tree where the comment exists.
- This is important for root-scoped filtering in notification inbox and top nav badge behavior.

## 5) Which users are notified

Current Page-comment behavior notifies:
- Actors that have RecordingStudio::Access records under the same root recording
- Excluding the comment author

Business interpretation:
- Anyone with view-level participation in that workspace can be notified.
- The commenter does not get notified about their own comment.

## 6) How notification creation is validated and persisted

Primary service:
- lib/recording_studio_notifications/services/notify.rb

Key responsibilities in the service:
- Validates required inputs (recipient, title, registered type, channels)
- Validates root-scope consistency (root/recording/notifiable alignment)
- Sanitizes URL safety
- Applies authorization checks if the type has creation_action
- Creates Notification and Delivery rows in a transaction
- Enqueues delivery job (or runs immediately) depending on config

Core behavior excerpt:

```ruby
notification = find_idempotent_notification || create_notification!
create_deliveries!(notification)
should_deliver = notification.previously_new_record? || notification.deliveries.pending.exists?
enqueue_or_deliver!(notification) if should_deliver
```

Why this pattern:
- Transaction + idempotency protects against duplicates.
- Delivery rows separate notification metadata from channel dispatch status.

## 7) Channel behavior and why only in-app is active

Channel registry is in:
- lib/recording_studio_notifications/channel_registry.rb

Built-in in-app adapter:

```ruby
module RecordingStudioNotifications
  module Channels
    class InAppAdapter
      def deliver(notification:, delivery:)
        delivery.mark_delivered!
        notification
      end
    end
  end
end
```

Current status in this repo:
- in_app channel is registered by default.
- Page comment type allows only in_app.
- No email/SMS/push adapters are configured by default here.

## 8) ActiveJob, Redis, Sidekiq, Solid Queue: what is used here

What the engine uses:
- ActiveJob abstraction for delivery jobs:
  - app/jobs/recording_studio_notifications/application_job.rb
  - app/jobs/recording_studio_notifications/delivery_job.rb

How jobs are queued:
- notify service enqueues DeliveryJob via perform_later when deliver_later is true.
- queue name is configurable via RecordingStudioNotifications.configuration.queue_name.

Backend details in this dummy app:
- test/dummy/Gemfile includes solid_queue gem.
- Environment files do not explicitly set config.active_job.queue_adapter.
- Therefore, actual adapter behavior follows Rails/default app configuration unless you explicitly set one.

Important takeaway:
- This engine is adapter-agnostic by design.
- You can run with async, Solid Queue, Sidekiq, etc., by configuring ActiveJob in the host app.
- Redis/Sidekiq are not required by this engine itself.

## 9) From UI action to hook trigger

Page comment POST endpoint:
- test/dummy/config/routes.rb

```ruby
resources :pages, only: %i[index show new create] do
  member do
    post :comment
  end
end
```

Controller action that creates the comment:
- test/dummy/app/controllers/pages_controller.rb

```ruby
result = RecordingStudioCommentable::Services::CreateComment.call(
  parent_recording: @page_recording,
  body: body,
  author: current_user
)
```

Why this matters:
- The notification hook is attached to CreateComment service completion.
- If this service does not succeed, the hook does not notify.

## 10) Reading, unread, archiving, and click-to-open

Engine routes:
- config/routes.rb

```ruby
resources :notifications, only: %i[index show] do
  member do
    get :open
    patch :mark_read
    patch :mark_unread
    patch :archive
  end
end
```

Click-open behavior:
- app/controllers/recording_studio_notifications/notifications_controller.rb

```ruby
def open
  @notification.mark_read! if @notification.unread?
  destination = @notification.url.presence || notification_path(@notification)
  redirect_to destination, allow_other_host: true
end
```

Meaning for users:
- Clicking a notification both updates read status and takes user to the relevant page.

## 11) Template for adding a brand-new notification type

Use this as a repeatable checklist.

1. Register the type:

```ruby
# config/initializers/recording_studio_notifications.rb
RecordingStudioNotifications.configure do |config|
  config.notification_types.register(
    :task_assigned,
    label: "Task assigned",
    description: "A user was assigned to a task.",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :root
  )
end
```

2. Trigger notification at the correct business event:
- Prefer hook/event callbacks after successful service execution.
- Build recipient list carefully and avoid self-notifications when appropriate.
- Always pass root_recording when using :root scope.

3. Call notification service:

```ruby
RecordingStudioNotifications.notify(
  notification_type: :task_assigned,
  recipient: assignee,
  actor: current_user,
  recording: task_recording,
  root_recording: task_recording.root_recording,
  title: "Task assigned: #{task.title}",
  body: "#{current_user.email} assigned you a task",
  url: Rails.application.routes.url_helpers.task_path(task),
  idempotency_key: "task-assigned-#{task.id}-#{assignee.id}"
)
```

4. Verify UI and state transitions:
- Notification appears in bell/inbox
- Clicking marks read and redirects
- mark_unread and archive endpoints work as expected

## 12) Why this architecture is used

For engineering:
- Hooks decouple domain actions (comments) from notification engine internals.
- Type registry enforces valid, documented notification contracts.
- Delivery rows allow channel-level retries/visibility.
- ActiveJob abstraction keeps backend choice flexible.

For product and PM:
- Easy to add new notification scenarios without rewriting core engine logic.
- Clear ownership boundaries: feature teams define events/recipients; engine handles consistency and delivery mechanics.
- Read/unread/archive lifecycle is standardized across notification types.

## 13) Common pitfalls and safeguards

Pitfalls:
- Registering a type with wrong scope and missing root_recording.
- Not using idempotency_key for repeatable hooks.
- Not excluding actor from recipient list.
- Creating unsafe URLs.

Safeguards already present:
- Scope validation in Notification + Notify service.
- URL safety checks.
- Idempotency support.
- Authorization hooks for creation_action (if configured).

---

If you want, a follow-up guide can map this into a one-page sequence diagram for stakeholder presentations.