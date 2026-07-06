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

    if @page.save
      redirect_to pages_path, notice: "Page created."
    else
      render :new, status: :unprocessable_entity
    end
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
end