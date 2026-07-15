===============================================================================

RecordingStudioNotifications has been installed successfully!

The engine has been mounted at /recording_studio_notifications in your application.

Next steps:
1. Review config/initializers/recording_studio_notifications.rb and register your notification types.
2. Run `bin/rails generate recording_studio_notifications:migrations`.
3. Run `bin/rails db:migrate`.
4. Call `RecordingStudioNotifications.notify(...)` from app code or enqueue `RecordingStudioNotifications::NotifyJob`.
5. Register custom channel adapters for email, webhook, or provider delivery when a public outgoing API is available.

If you use Tailwind CSS:
1. Run 'bin/rails tailwindcss:build' to rebuild your CSS with RecordingStudioNotifications styles

To use the engine:
1. Start your Rails server
2. Visit http://localhost:3000/recording_studio_notifications

===============================================================================
