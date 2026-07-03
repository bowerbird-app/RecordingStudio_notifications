# frozen_string_literal: true

class AdminAuditLog < ApplicationRecord
  def self.record_admin_action!(event)
    create!(
      event_id: event.id,
      resource_key: event.resource_key,
      action_key: event.action_key,
      outcome: event.outcome,
      actor_type: record_type_for(event.actor),
      actor_id: record_id_for(event.actor),
      record_type: record_type_for(event.record),
      record_id: record_id_for(event.record),
      access_recording_id: record_id_for(event.access_recording),
      surface_key: event.surface_key,
      http_method: event.http_method,
      destructive: event.destructive,
      required_role: event.required_role,
      blast_radius: event.blast_radius,
      request_id: event.request_id,
      ip_address: event.ip_address,
      user_agent: event.user_agent,
      metadata: event.metadata,
      error_class: event.error_class,
      error_message: event.error_message,
      recording_studio_event_id: record_id_for(event.recording_studio_event),
      occurred_at: Time.current
    )
  end

  def self.record_type_for(record)
    record.class.name if record
  end

  def self.record_id_for(record)
    return unless record
    return record.id.to_s if record.respond_to?(:id)

    record.to_s
  end
end