# frozen_string_literal: true

require_relative "api/gate"
require_relative "api/query"
require_relative "api/serialize"
require_relative "api/inbox"
require_relative "api/show"
require_relative "api/member_action"
require_relative "api/preferences"

module RecordingStudioNotifications
  # Registers public inbox, member, and preference endpoints when Recording Studio API is loaded.
  # MCP advertises registered endpoints automatically. This gem adds no MCP tools.
  module Api
    INDEX_NAME = "notifications.inbox"
    SHOW_NAME = "notifications.show"
    MARK_READ_NAME = "notifications.mark_read"
    MARK_UNREAD_NAME = "notifications.mark_unread"
    ARCHIVE_NAME = "notifications.archive"
    UNARCHIVE_NAME = "notifications.unarchive"
    PREFERENCES_NAME = "notifications.preferences"
    UPDATE_PREFERENCES_NAME = "notifications.update_preferences"
    INDEX_PATH = "notifications"
    MEMBER_PATH = "notifications/:id"
    PREFERENCES_PATH = "notifications/preferences"

    ENDPOINTS = [
      {
        name: INDEX_NAME, http_verb: :get, path: INDEX_PATH, handler: Inbox,
        openapi: Inbox::OPENAPI, input_contract: Inbox::INPUT_CONTRACT
      },
      {
        name: SHOW_NAME, http_verb: :get, path: MEMBER_PATH, handler: Show,
        openapi: Show::OPENAPI, input_contract: Show::INPUT_CONTRACT
      },
      {
        name: MARK_READ_NAME, http_verb: :post, path: "#{MEMBER_PATH}/mark_read", handler: MarkRead,
        openapi: MarkRead::OPENAPI, input_contract: MarkRead::INPUT_CONTRACT
      },
      {
        name: MARK_UNREAD_NAME, http_verb: :post, path: "#{MEMBER_PATH}/mark_unread", handler: MarkUnread,
        openapi: MarkUnread::OPENAPI, input_contract: MarkUnread::INPUT_CONTRACT
      },
      {
        name: ARCHIVE_NAME, http_verb: :post, path: "#{MEMBER_PATH}/archive", handler: Archive,
        openapi: Archive::OPENAPI, input_contract: Archive::INPUT_CONTRACT
      },
      {
        name: UNARCHIVE_NAME, http_verb: :post, path: "#{MEMBER_PATH}/unarchive", handler: Unarchive,
        openapi: Unarchive::OPENAPI, input_contract: Unarchive::INPUT_CONTRACT
      },
      {
        name: PREFERENCES_NAME, http_verb: :get, path: PREFERENCES_PATH, handler: Preferences,
        openapi: Preferences::OPENAPI
      },
      {
        name: UPDATE_PREFERENCES_NAME, http_verb: :patch, path: PREFERENCES_PATH, handler: UpdatePreferences,
        openapi: UpdatePreferences::OPENAPI, input_contract: UpdatePreferences::INPUT_CONTRACT
      }
    ].freeze

    class << self
      def register!
        return unless defined?(::RecordingStudioApi)

        RecordingStudioApi.configuration.each_api do |api|
          ENDPOINTS.each { |endpoint| register_endpoint!(endpoint, api: api.name) }
        end
        true
      end

      def already_registered?(name, api:)
        RecordingStudioApi.registered_endpoint(name, api: api).present?
      end

      def register_endpoint!(endpoint, api:)
        return if already_registered?(endpoint.fetch(:name), api: api)

        RecordingStudioApi.register_endpoint(
          endpoint.fetch(:name),
          api: api,
          http_verb: endpoint.fetch(:http_verb),
          path: endpoint.fetch(:path),
          handler: endpoint.fetch(:handler),
          openapi: endpoint.fetch(:openapi),
          input_contract: endpoint[:input_contract]
        )
      end
    end
  end
end
