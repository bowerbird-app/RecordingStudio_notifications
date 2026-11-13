# frozen_string_literal: true

# Root Switchable 0.15 refuses the switch page unless the actor can :view
# the current root. The dummy all-workspaces list still includes every
# workspace, and the current root is the first of that list.
module SwitchPageAccess
  def ensure_switch_page_view!(actor)
    recording = first_all_workspaces_root
    return if actor.blank? || recording.blank?
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

    if RecordingStudioAccessible.access_recordings_for(recording).none?
      bootstrap_switch_page_owner!(actor, recording)
    else
      grant_switch_page_view!(actor, recording)
    end
  end

  def first_all_workspaces_root
    workspace_roots = Workspace.order(:name).filter_map do |workspace|
      RecordingStudio.root_recording_for(workspace)
    end
    admin_root = AdminRoot.first
    admin_roots = admin_root ? [RecordingStudio.root_recording_for(admin_root)] : []

    (workspace_roots + admin_roots).uniq(&:id).first
  end

  private

  def bootstrap_switch_page_owner!(actor, recording)
    previous_actor = Current.actor
    Current.actor = actor
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?
  ensure
    Current.actor = previous_actor
  end

  def grant_switch_page_view!(actor, recording)
    manager = switch_page_manager_for(recording)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: :view,
      manager_actor: manager
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  def switch_page_manager_for(recording)
    RecordingStudioAccessible.access_recordings_for(recording).filter_map { |access_recording|
      access_recording.recordable&.actor
    }.find { |candidate|
      RecordingStudioAccessible.authorized?(actor: candidate, recording: recording, role: :edit)
    }
  end
end

ActiveSupport::TestCase.include(SwitchPageAccess)
