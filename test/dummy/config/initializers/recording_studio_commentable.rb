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

  # Collect workspace access recordings under this root.
  # These represent users who can see this workspace.
  workspace_viewers = RecordingStudio::Recording.unscoped
    # Restrict to access records directly under the root and not trashed.
    .where(
      parent_recording_id: root_recording.id,
      recordable_type: "RecordingStudio::Access",
      trashed_at: nil
    )
    # Map each access recording to its actor (for example, a User).
    .map { |r| r.recordable&.actor }
    # Remove nil actors caused by incomplete access rows.
    .compact
    # Avoid notifying the same person who wrote the comment.
    .reject { |actor| actor == comment.author }

  # Stop when there is no one else to notify.
  next if workspace_viewers.empty?

  # Build the destination URL for notification clicks.
  url = Rails.application.routes.url_helpers.page_path(page_recordable)
  # Create one notification per recipient.
  workspace_viewers.each do |viewer|
    # Send an in-app notification for the new page comment.
    RecordingStudioNotifications.notify(
      # Use the registered notification type for page comments.
      notification_type: :page_comment,
      # Recipient who should receive this notification.
      recipient: viewer,
      # Actor who triggered the event (the commenter).
      actor: comment.author,
      # Recording context for authorization/visibility checks.
      recording: comment_recording,
      # Root context so notifications are scoped to the correct workspace.
      root_recording: root_recording,
      # Human-readable title displayed in the UI.
      title: "New comment on #{page_recordable.title}",
      # Message body, truncated for compact notification display.
      body: comment.body.to_s,
      # URL opened when the recipient clicks the notification.
      url: url,
      # Idempotency key prevents duplicate notifications per comment+recipient.
      idempotency_key: "comment-#{comment.id}-#{viewer.id}"
    )
  end
rescue StandardError => e
  # Keep app flow resilient by logging failures instead of crashing requests.
  Rails.logger.warn "[RecordingStudioNotifications] Comment hook failed: #{e.message}" if defined?(Rails)
end