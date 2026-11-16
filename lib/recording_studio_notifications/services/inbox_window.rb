# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    # A page of inbox groups from an InboxScope relation.
    #
    # With rollup delivery on, the page is whole groups. A shown group includes
    # every notice in it.
    #
    # Without root ids in SQL, visible_notification? runs before the page is cut.
    # A LIMIT before that check drops a notice the person can see.
    class InboxWindow
      ROW_BATCH = 100
      GROUP_ID = /
        \Anotification-group-
        (.+)
        -
        (#{NotificationTypeRegistry::CADENCES.map { |cadence| Regexp.escape(cadence.to_s) }.join('|')})
        -
        (.+)
        \z
      /x

      Window = Struct.new(:rows, :more, :unread_count, keyword_init: true)
      GroupPage = Struct.new(:group, :rows, :more, keyword_init: true)
      GroupRef = Struct.new(:id)

      def self.page(relation, recipient:, limit:, offset:, &visible)
        if InboxScope.authorized_root_recording_ids_supported?
          sql_page(relation, recipient:, limit:, offset:)
        else
          ruby_page(relation, recipient:, limit:, offset:, &visible)
        end
      end

      def self.group_page(relation, recipient:, group_id:, limit:, offset:)
        identity = group_identity(relation, recipient:, group_id:)
        return unless identity

        scope = membership_scope(relation, identity)
        rows = scope.offset(offset).limit(limit).to_a
        more = rows.size == limit && scope.offset(offset + limit).pick(:id).present?
        GroupPage.new(group: GroupRef.new(identity.id), rows:, more:)
      end

      def self.sql_page(relation, recipient:, limit:, offset:)
        unread_count = InboxScope.unread_count(relation)
        if RecordingStudioNotifications.configuration.rollup_delivery_enabled
          grouped_page(relation, recipient:, limit:, offset:, unread_count:)
        else
          exact_page(relation, limit:, offset:, unread_count:)
        end
      end
      private_class_method :sql_page

      def self.exact_page(relation, limit:, offset:, unread_count:)
        rows = relation.offset(offset).limit(limit).to_a
        more = rows.size == limit && relation.offset(offset + limit).pick(:id).present?
        Window.new(rows:, more:, unread_count:)
      end
      private_class_method :exact_page

      def self.grouped_page(relation, recipient:, limit:, offset:, unread_count:)
        identities = group_identities(relation, recipient:, needed: offset + limit)
        more = identities.size > offset + limit
        page_identities = identities.drop(offset).take(limit)
        Window.new(rows: rows_for(relation, page_identities), more:, unread_count:)
      end
      private_class_method :grouped_page

      def self.group_identities(relation, recipient:, needed:)
        grouping = grouping_for(recipient)
        identities = []
        seen = {}
        row_offset = 0

        loop do
          batch = relation.offset(row_offset).limit(ROW_BATCH).pluck(:id, :notification_type, :created_at)
          break if batch.empty?

          batch.each do |notification_id, notification_type, created_at|
            identity = grouping.group_identity(
              notification_type:,
              created_at:,
              notification_id:
            )
            next if seen[identity.id]

            seen[identity.id] = true
            identities << identity
            return identities if identities.size > needed
          end

          row_offset += batch.size
          break if batch.size < ROW_BATCH
        end

        identities
      end
      private_class_method :group_identities

      def self.grouping_for(recipient)
        saved = if RecordingStudioNotifications.configuration.rollup_delivery_enabled
                  Preference.where(recipient: recipient, channel: nil).index_by do |preference|
                    preference.notification_type.to_s
                  end
                end
        InboxGrouping.new(recipient: recipient, notifications: [], preferences: saved)
      end
      private_class_method :grouping_for

      def self.rows_for(relation, identities)
        return [] if identities.empty?

        table = Notification.arel_table
        clause = identities.map { |identity| membership_clause(table, identity) }.reduce(&:or)
        relation.where(clause).to_a
      end
      private_class_method :rows_for

      def self.membership_clause(table, identity)
        if identity.cadence.to_sym == :individual
          table[:id].eq(identity.notification_id)
        else
          table[:notification_type].eq(identity.notification_type.to_s)
                                   .and(table[:created_at].gteq(identity.starts_at))
                                   .and(table[:created_at].lt(identity.ends_at))
        end
      end
      private_class_method :membership_clause

      def self.membership_scope(relation, identity)
        if identity.cadence.to_sym == :individual
          relation.where(id: identity.notification_id)
        else
          relation.where(notification_type: identity.notification_type.to_s)
                  .where(created_at: identity.starts_at...identity.ends_at)
        end
      end
      private_class_method :membership_scope

      def self.group_identity(relation, recipient:, group_id:)
        match = GROUP_ID.match(group_id.to_s)
        return unless match

        type_name, cadence_name, suffix = match.captures
        grouping = grouping_for(recipient)
        identity = if cadence_name == "individual"
                     row = relation.where(id: suffix).pick(:id, :notification_type, :created_at)
                     return unless row

                     grouping.group_identity(notification_type: row[1], created_at: row[2], notification_id: row[0])
                   else
                     grouping.group_identity(
                       notification_type: type_name,
                       created_at: Time.zone.at(Integer(suffix)),
                       notification_id: nil
                     )
                   end
        return unless identity.id == group_id && identity.cadence.to_s == cadence_name
        return unless membership_scope(relation, identity).pick(:id)

        identity
      rescue ArgumentError, TypeError, RangeError
        nil
      end
      private_class_method :group_identity

      def self.ruby_page(relation, recipient:, limit:, offset:, &visible)
        visible_rows = InboxScope.rows(relation, &visible)
        groups = InboxGrouping.new(recipient:, notifications: visible_rows).call.flat_map(&:groups)
        ordered = groups.sort_by { |group| [group.latest_notification.created_at, group.id] }.reverse
        page_groups = ordered.drop(offset).take(limit)
        Window.new(
          rows: page_groups.flat_map(&:notifications),
          more: ordered.size > offset + limit,
          unread_count: visible_rows.count(&:unread?)
        )
      end
      private_class_method :ruby_page
    end
  end
end
