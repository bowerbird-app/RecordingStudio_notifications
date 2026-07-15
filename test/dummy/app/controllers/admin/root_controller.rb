# frozen_string_literal: true

class Admin::RootController < Admin::BaseController
  SEARCH_RESULTS_FRAME_ID = "admin-root-search-results"

  def show
    @admin_access_recording = recording_studio_admin_access_recording
    @admin_search_query = params[:q].to_s.strip
    load_admin_search_results

    if turbo_frame_request? && request.headers["Turbo-Frame"] == SEARCH_RESULTS_FRAME_ID
      render partial: "search_results"
      return
    end

    @admin_sections = recording_studio_admin_context.available_admin_sections(recording: @admin_access_recording)
  end

  private

  def load_admin_search_results
    @admin_search_results = if @admin_search_query.present?
                              recording_studio_admin_context.available_admin_items(
                                recording: @admin_access_recording,
                                include: %i[sections screens]
                              )
                            else
                              []
                            end
    @normalized_admin_search_query = @admin_search_query.downcase
    @matching_admin_search_results = if @admin_search_query.present?
                                       @admin_search_results.count do |item|
                                         item.search_text.include?(@normalized_admin_search_query)
                                       end
                                     else
                                       0
                                     end
  end
end
