# frozen_string_literal: true

class DocsController < ApplicationController
  def install
  end

  def configuration
    render :config
  end

  def recordable_types
    RecordingStudio.validate_recordable_declarations!

    @recordable_types = RecordingStudio.recordable_declarations.values.sort_by(&:type).map do |declaration|
      normalize_recordable_declaration(declaration)
    end
  end

  def recordings_tree
    recordings = RecordingStudio::Recording.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)

    @recording_tree = recordings_by_parent_id.fetch(nil, []).map do |recording|
      build_recording_node(recording, recordings_by_parent_id)
    end
  end

  def gem_views
    prefix = "#{RecordingStudioNotifications::Engine.root}/"

    @engine_views = Dir.glob(RecordingStudioNotifications::Engine.root.join("app/views/recording_studio_notifications/**/*.erb").to_s)
      .sort
      .map { |path| path.delete_prefix(prefix) }
  end

  def gem_view
    view_path = params[:view]

    unless valid_engine_view?(view_path)
      redirect_to docs_gem_views_path, alert: "Invalid view path."
      return
    end

    @view_path = view_path
    @engine_template = view_path.sub(%r{^app/views/}, "").sub(/\.erb$/, "")
    setup_gem_view_data(view_path)
  end

  def all_notifications
    setup_gem_view_data("app/views/recording_studio_notifications/notifications/index.html.erb")
    @engine_template = "recording_studio_notifications/notifications/index"
    render :gem_view
  end

  def notification_detail
    setup_gem_view_data("app/views/recording_studio_notifications/notifications/show.html.erb")
    @engine_template = "recording_studio_notifications/notifications/show"
    render :gem_view
  end

  def notification_settings
    setup_gem_view_data("app/views/recording_studio_notifications/settings/show.html.erb")
    @engine_template = "recording_studio_notifications/settings/show"
    render :gem_view
  end

  def methods
  end

  private

  def normalize_recordable_declaration(declaration)
    {
      name: declaration.type,
      label: declaration.label,
      root: declaration.root?,
      allowed_parent_types: RecordingStudio.allowed_parent_types_for(declaration.type),
      recordings_count: RecordingStudio::Recording.where(recordable_type: declaration.type).count,
      recordables_count: count_recordables_for(declaration.type)
    }
  end

  def count_recordables_for(type_name)
    recordable_class = type_name.safe_constantize
    return 0 unless recordable_class&.<= ActiveRecord::Base
    return 0 unless recordable_class.table_exists?

    recordable_class.count
  rescue ActiveRecord::ActiveRecordError
    0
  end

  def build_recording_node(recording, recordings_by_parent_id)
    {
      label: recording_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_recording_node(child_recording, recordings_by_parent_id)
      end
    }
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)

    "#{type_label}: #{identifier}"
  end

  def recordable_identifier(recordable)
    return "Unknown recordable" if recordable.nil?

    %i[name title email label slug identifier].each do |attribute|
      next unless recordable.respond_to?(attribute)

      value = recordable.public_send(attribute)
      return value if value.present?
    end

    actor = recordable.actor if recordable.respond_to?(:actor)
    actor_email = actor.email if actor&.respond_to?(:email) && actor.email.present?

    if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
      return "#{recordable.role.to_s.humanize} for #{actor_email}"
    end

    return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end

  def valid_engine_view?(view_path)
    return false if view_path.blank?
    return false if view_path.include?("..") || view_path.start_with?("/")

    allowed_views = Dir.glob(
      RecordingStudioNotifications::Engine.root.join("app/views/recording_studio_notifications/**/*.erb").to_s
    ).map { |p| p.delete_prefix("#{RecordingStudioNotifications::Engine.root}/") }

    allowed_views.include?(view_path)
  end

  def setup_gem_view_data(view_path)
    # Provide enough dummy data so engine views don't crash.
    # Each view sets up what it needs; missing ivars default to nil/[].

    if view_path.include?("notifications/index")
      @notifications = RecordingStudioNotifications::Notification.none
      @inbox_scope = "all"
      @current_root_recording = nil
    elsif view_path.include?("notifications/show")
      @notification = RecordingStudioNotifications::Notification.new(
        notification_type: "sample",
        title: "Sample notification",
        body: "This is a sample notification body for preview purposes.",
        url: nil,
        created_at: Time.current
      )
    elsif view_path.include?("settings/show")
      @notification_types = RecordingStudioNotifications.notification_types.values
      @preferences = {}
    end
  end
end
