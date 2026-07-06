class PagesController < ApplicationController
  def index
    @pages = scoped_pages.order(created_at: :desc)
  end

  def show
    @page = scoped_pages.find(params[:id])
    @page_recording = find_page_recording
  rescue ActiveRecord::RecordNotFound
    redirect_to pages_path, alert: "Page not found."
  end

  def new
    @page = Page.new
  end

  def create
    @page = Page.new(page_params)
    current_root = current_root_for_create
    page_recording = nil

    ActiveRecord::Base.transaction do
      @page.save!
      page_recording = ensure_page_recording!(@page, current_root: current_root)
    end

    notify_workspace_users_page_created!(
      page: @page,
      page_recording: page_recording,
      root_recording: current_root
    )

    redirect_to pages_path, notice: "Page created."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def comment
    @page = Page.find(params[:id])
    @page_recording = RecordingStudio::Recording.find_by(recordable: @page, trashed_at: nil)

    unless @page_recording
      redirect_to page_path(@page), alert: "Page is not recorded in a workspace."
      return
    end

    body = params[:body].presence || params.dig(:recording_studio_commentable_comment, :body)

    result = RecordingStudioCommentable::Services::CreateComment.call(
      parent_recording: @page_recording,
      body: body,
      author: current_user
    )

    if result.success?
      redirect_to page_path(@page), notice: "Comment posted."
    else
      redirect_to page_path(@page), alert: result.error.presence || "Could not post comment."
    end
  end

  private

  def scoped_pages
    return Page.all unless respond_to?(:current_root_recording, true)

    current_root = send(:current_root_recording)
    return Page.all if current_root.blank?

    recording_ids = RecordingStudio::Recording
      .where(root_recording: current_root, recordable_type: "Page", trashed_at: nil)
      .pluck(:recordable_id)

    Page.where(id: recording_ids)
  end

  def page_params
    params.require(:page).permit(:title)
  end

  def find_page_recording
    RecordingStudio::Recording.find_by(
      recordable: @page,
      trashed_at: nil
    )
  end

  def ensure_page_recording!(page, current_root:)
    return if current_root.blank?

    existing = RecordingStudio::Recording.find_by(
      root_recording: current_root,
      recordable: page,
      trashed_at: nil
    )
    return existing if existing

    RecordingStudio.record!(
      action: "created",
      recordable: page,
      root_recording: current_root,
      parent_recording: current_root
    ).recording
  end

  def current_root_for_create
    return nil unless respond_to?(:current_root_recording, true)

    send(:current_root_recording)
  end

  def notify_workspace_users_page_created!(page:, page_recording:, root_recording:)
    return if root_recording.blank? || page_recording.blank?

    workspace_recipients_for(root_recording).each do |recipient|
      next if recipient == current_user

      RecordingStudioNotifications.notify(
        notification_type: :page_created,
        recipient: recipient,
        actor: current_user,
        recording: page_recording,
        root_recording: root_recording,
        title: "New page created: #{page.title}",
        body: "#{current_user.display_name} created a new page in this workspace.",
        url: page_path(page),
        idempotency_key: "page-created-#{page.id}-#{recipient.id}"
      )
    end
  end

  def workspace_recipients_for(root_recording)
    RecordingStudio::Recording.unscoped
      .where(
        parent_recording_id: root_recording.id,
        recordable_type: "RecordingStudio::Access",
        trashed_at: nil
      )
      .map { |recording| recording.recordable&.actor }
      .compact
      .uniq { |actor| [actor.class.name, actor.id] }
  end
end