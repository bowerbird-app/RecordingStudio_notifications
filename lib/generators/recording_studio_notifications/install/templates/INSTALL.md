RecordingStudioNotifications install complete.

Next steps:

1. Review config/initializers/recording_studio_notifications.rb, register the notification types your app emits, and set `config.polling_interval_seconds` if you want a polling cadence other than the default 60 seconds.
2. If you use environment-specific settings, create config/recording_studio_notifications.yml.
3. Install the engine migrations with `bin/rails generate recording_studio_notifications:migrations`.
4. Apply the migrations with `bin/rails db:migrate`.
5. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
6. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
7. Use `RecordingStudioNotifications.notify(...)` or enqueue `RecordingStudioNotifications::NotifyJob` from your app code.
8. The bundled channel is `:in_app`. Webhook delivery is intentionally a seam: register a channel adapter when your host app exposes a public outgoing provider API.