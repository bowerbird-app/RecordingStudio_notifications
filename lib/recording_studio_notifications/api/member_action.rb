# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class MemberAction
      def self.call(context)
        notification = Gate.visible_notification!(context, include_archived: include_archived?)
        notification.public_send(mutation)
        Serialize.notification(notification)
      end

      def self.include_archived?
        false
      end

      def self.mutation
        raise NotImplementedError, "#{name} must define mutation"
      end

      def self.id_contract
        {
          reject_unknown: false,
          fields: {
            id: {
              type: :string,
              required: true,
              description: ToolDescriptions::ID
            }
          }
        }
      end

      def self.openapi(title, description)
        {
          title: title,
          summary: title,
          description: description,
          tags: ["Notifications"]
        }
      end
    end

    class MarkRead < MemberAction
      TITLE = "Notifications - Mark read"
      OPENAPI = openapi(
        TITLE,
        ToolDescriptions::MARK_READ
      ).freeze
      INPUT_CONTRACT = id_contract.freeze

      def self.mutation
        :mark_read!
      end
    end

    class MarkUnread < MemberAction
      TITLE = "Notifications - Mark unread"
      OPENAPI = openapi(
        TITLE,
        ToolDescriptions::MARK_UNREAD
      ).freeze
      INPUT_CONTRACT = id_contract.freeze

      def self.mutation
        :mark_unread!
      end
    end

    class Archive < MemberAction
      TITLE = "Notifications - Archive"
      OPENAPI = openapi(
        TITLE,
        ToolDescriptions::ARCHIVE
      ).freeze
      INPUT_CONTRACT = id_contract.freeze

      def self.mutation
        :archive!
      end
    end

    class Unarchive < MemberAction
      TITLE = "Notifications - Unarchive"
      OPENAPI = openapi(
        TITLE,
        ToolDescriptions::UNARCHIVE
      ).freeze
      INPUT_CONTRACT = id_contract.freeze

      def self.mutation
        :unarchive!
      end

      def self.include_archived?
        true
      end
    end
  end
end
