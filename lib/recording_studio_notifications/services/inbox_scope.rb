# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    # Inbox rows for one recipient: active, in the inbox, not waiting on an
    # in-app rollup, and not tied to a trashed root. When Accessible can list
    # viewable roots in SQL, root view is part of that relation. Otherwise the
    # caller keeps the per-row check.
    class InboxScope
      VIEW_ROLE = :view

      def self.authorized_root_recording_ids_supported?
        return false unless defined?(::RecordingStudioAccessible)
        return false unless ::RecordingStudioAccessible.respond_to?(:authorized_root_recording_ids_supported?)

        ::RecordingStudioAccessible.authorized_root_recording_ids_supported?
      end

      def self.relation(recipient:, actor:, root_recording: nil, inbox_scope: nil)
        new(recipient:, actor:, root_recording:, inbox_scope:).relation
      end

      def self.unread_count(relation)
        relation.unread.except(:order).count
      end

      def self.clear_unread!(relation, at: Time.current)
        relation.unread.except(:order).update_all(cleared_at: at, updated_at: at)
      end

      def self.rows(relation, &visible)
        return relation.to_a if authorized_root_recording_ids_supported?

        relation.select { |notification| visible.call(notification) }
      end

      def self.unread_total(relation, rows)
        return unread_count(relation) if authorized_root_recording_ids_supported?

        rows.count(&:unread?)
      end

      def self.clear_visible_unread!(relation, &visible)
        unless authorized_root_recording_ids_supported?
          visible_ids = relation.select { |notification| visible.call(notification) }.map(&:id)
          relation = relation.where(id: visible_ids)
        end
        clear_unread!(relation)
      end

      def initialize(recipient:, actor:, root_recording:, inbox_scope:)
        @recipient = recipient
        @actor = actor
        @root_recording = root_recording
        @inbox_scope = inbox_scope
      end

      def relation
        notifications = Notification.for_recipient(@recipient).active.visible_in_inbox.in_inbox
        notifications = notifications.for_current_root_inbox(@root_recording) if @inbox_scope == "current_root"
        notifications = exclude_trashed_roots(notifications)
        notifications = with_viewable_roots(notifications) if self.class.authorized_root_recording_ids_supported?
        notifications.newest_first
      end

      private

      def exclude_trashed_roots(notifications)
        roots = RecordingStudio::Recording.arel_table
        trashed = RecordingStudio::Recording.unscoped.where(
          roots[:id].eq(Notification.arel_table[:root_recording_id])
        ).where.not(trashed_at: nil)
        notifications.where(Arel::Nodes::Not.new(trashed.arel.exists))
      end

      def with_viewable_roots(notifications)
        allowed = RecordingStudioAccessible.authorized_root_recording_ids(actor: @actor, role: VIEW_ROLE)
        column = Notification.arel_table[:root_recording_id]
        viewable = column.eq(nil).or(column.in(allowed.arel))
        notifications.where(viewable)
      end
    end
  end
end
