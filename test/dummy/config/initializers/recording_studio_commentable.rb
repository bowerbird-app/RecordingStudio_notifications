# frozen_string_literal: true

# Freeze string literals in this file for consistency and minor memory savings.

# Register a post-service hook in RecordingStudioCommentable.
# This runs after services complete, letting us react to successful comment creation.
RecordingStudioCommentable.configuration.hooks.after_service(priority: 10) do |service_class, result|
  # Only react to the CreateComment service.
  next unless service_class == RecordingStudioCommentable::Services::CreateComment
  # Stop unless the comment service completed successfully.
  next unless result.success?

  # Extract the created comment object from the result payload.
  comment = result.value
  # Find the RecordingStudio recording node that wraps this comment.
  comment_recording = RecordingStudio::Recording.find_by(recordable: comment)
  # Stop if no recording exists for the comment.
  next unless comment_recording

  # Resolve the parent recording (expected to be the page's recording).
  parent_recording = comment_recording.parent_recording
  # Stop if the comment has no parent recording.
  next unless parent_recording

  # Resolve the domain object behind the parent recording.
  page_recordable = parent_recording.recordable
  # Only continue when the parent is a Page.
  next unless page_recordable.is_a?(Page)

  # Resolve workspace root for this comment thread.
  root_recording = comment_recording.root_recording
  # Stop if we cannot determine a root recording.
  next unless root_recording

  url = Rails.application.routes.url_helpers.page_path(page_recordable)
  RecordingStudioNotifications.notify_fan_out(
    recipient_scope: :page_comment_viewers,
    notification_type: :page_comment,
    actor: comment.author,
    notifiable: comment,
    recording: comment_recording,
    root_recording: root_recording,
    title: "New comment on #{page_recordable.title}",
    body: comment.body.to_s,
    url: url,
    idempotency_key: "comment-#{comment.id}"
  )
rescue StandardError => e
  # Keep app flow resilient by logging failures instead of crashing requests.
  Rails.logger.warn "[RecordingStudioNotifications] Comment hook failed: #{e.message}" if defined?(Rails)
end