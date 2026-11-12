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
    CLEAR_NAME = "notifications.clear"
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
        name: CLEAR_NAME, http_verb: :post, path: "#{MEMBER_PATH}/clear", handler: Clear,
        openapi: Clear::OPENAPI, input_contract: Clear::INPUT_CONTRACT
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
        return unless available?

        ENDPOINTS.each { |endpoint| register_endpoint!(endpoint) }
        true
      end

      def available?
        defined?(RecordingStudioApi) &&
          RecordingStudioApi.respond_to?(:register_endpoint) &&
          RecordingStudioApi.respond_to?(:registered_endpoint)
      end

      def already_registered?(name)
        return false unless available?

        RecordingStudioApi.registered_endpoint(name).present?
      end

      def register_endpoint!(endpoint)
        return if already_registered?(endpoint.fetch(:name))

        RecordingStudioApi.register_endpoint(
          endpoint.fetch(:name),
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
