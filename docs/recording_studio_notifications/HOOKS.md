# Service hooks

Register `before_service`, `around_service`, and `after_service` on `RecordingStudio.configuration.hooks`. That object is `RecordingStudio::Hooks` from Recording Studio 7.

`RecordingStudioNotifications::Services::Notify` and `RecordingStudioNotifications::Services::FanOut` call that registry. `RecordingStudioNotifications::Hooks` and `RecordingStudioNotifications.configuration.hooks` are gone.

The registry is shared with every other Recording Studio service. Check the service class. From `around_service`, call the block for every other service, or that service never runs.

## Register a hook

```ruby
RecordingStudio.configuration.hooks.before_service do |service_class, payload|
  next unless service_class == RecordingStudioNotifications::Services::Notify

  Rails.logger.info("notify #{payload[:notification_type]} for recipient #{payload[:recipient].id}")
end

RecordingStudio.configuration.hooks.around_service do |service, block|
  next block.call unless service.is_a?(RecordingStudioNotifications::Services::Notify)

  block.call
end

RecordingStudio.configuration.hooks.after_service do |service_class, notification|
  next unless service_class == RecordingStudioNotifications::Services::Notify

  Rails.logger.info("stored notification #{notification.id}")
end
```

`before_service` and `after_service` receive the service class, then the payload or the result. `around_service` receives the service instance and the block. Return the block's result when `notify` should return the notification.

Fan-out uses `RecordingStudioNotifications::Services::FanOut`. `before_service` and `after_service` receive that class. `around_service` receives an instance of that class.

## When the hooks run

`Notify` runs the three hooks after validation and authorization, around the create-and-deliver step. `notify` returns the notification. When no channel remains, `notify` returns `nil` before the hooks run.

`FanOut` runs the three hooks once per inserted recipient, after the insert and before the chunk commits. A retry that inserts nothing does not run them again.

The `before_service` payload has `notification_type`, `recipient`, `actor`, `notifiable`, `recording`, `root_recording`, and `channels`.

`after_service` receives whatever the around block returns. For these two services, that value is the stored notification.

## Instrumentation

These ActiveSupport notifications are unchanged.

- `notify.recording_studio_notifications`
- `deliver.recording_studio_notifications`
- `deliver_rollup.recording_studio_notifications`

`notify.recording_studio_notifications` fires inside the around block. `notify` fires it once per call. Fan-out fires it once per inserted recipient.
