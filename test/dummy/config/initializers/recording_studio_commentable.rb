# frozen_string_literal: true

# Bridge RS_commentable comment creation to RecordingStudioNotifications.
# Uses RS_commentable's own hook system — no monkey-patching.
if defined?(RecordingStudioCommentable) && defined?(RecordingStudioNotifications)
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

    # Notify all workspace members with view access except the comment author
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
  rescue StandardError => e
    Rails.logger.warn "[RecordingStudioNotifications] Comment hook failed: #{e.message}" if defined?(Rails)
  end
end