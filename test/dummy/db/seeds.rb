# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable,
    trashed_at: nil
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording
  ).recording
end

# Create the admin user
user = User.find_or_create_by!(email: "admin@admin.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end

# Create a commenter user for RS_commentable demonstration
commenter = User.find_or_create_by!(email: "commenter@commenter.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end

# Create the workspace recordables
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
accessible_workspace = Workspace.find_or_create_by!(name: "Client Workspace")
private_workspace = Workspace.find_or_create_by!(name: "Private Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

previous_actor = Current.actor
Current.actor = user

begin
  # Create the root recording
  root_recording = RecordingStudio.root_recording_for(workspace)
  accessible_root_recording = RecordingStudio.root_recording_for(accessible_workspace)
  private_root_recording = RecordingStudio.root_recording_for(private_workspace)
  admin_root = AdminRoot.first_or_create!
  admin_root_recording = RecordingStudio.root_recording_for(admin_root)

  folder_recording = find_or_record_child.call(folder, root_recording, root_recording)

  page_recording = find_or_record_child.call(page, root_recording, folder_recording)

  # Seed sample notifications for dummy app demonstration.
  RecordingStudioNotifications::Services::Notify.call(
    notification_type: :workspace_change,
    recipient: user,
    actor: user,
    root_recording: root_recording,
    recording: root_recording,
    title: "Workspace updated",
    body: "Studio Workspace settings changed.",
    idempotency_key: "seed-workspace-change-#{root_recording.id}"
  )

  RecordingStudioNotifications::Services::Notify.call(
    notification_type: :workspace_change,
    recipient: user,
    actor: user,
    root_recording: accessible_root_recording,
    recording: accessible_root_recording,
    title: "Client workspace updated",
    body: "Client Workspace preferences changed.",
    idempotency_key: "seed-workspace-change-#{accessible_root_recording.id}"
  )

  RecordingStudioNotifications::Services::Notify.call(
    notification_type: :workspace_change,
    recipient: user,
    actor: user,
    root_recording: private_root_recording,
    recording: private_root_recording,
    title: "Private workspace changed",
    body: "This should be hidden by Accessible view filtering.",
    idempotency_key: "seed-workspace-change-private-#{private_root_recording.id}"
  )

  RecordingStudioNotifications::Services::Notify.call(
    notification_type: :system_announcement,
    recipient: user,
    actor: user,
    title: "System maintenance",
    body: "Global announcement: maintenance window tonight.",
    idempotency_key: "seed-system-announcement"
  )

  if defined?(RecordingStudioAccessible) && RecordingStudioAccessible.respond_to?(:grant_access)
    ensure_access_for = lambda do |parent_recording, role|
      root_for_parent = RecordingStudio.root_recording_or_self(parent_recording)
      existing_grant = RecordingStudio::Recording.unscoped
        .where(
          root_recording_id: root_for_parent.id,
          parent_recording_id: parent_recording.id,
          recordable_type: "RecordingStudio::Access",
          trashed_at: nil
        )
        .order(created_at: :asc, id: :asc)
        .detect do |recording|
          access = recording.recordable
          access&.actor == user && access.role.to_s == role.to_s
        end

      next if existing_grant

      RecordingStudioAccessible::AccessCreationContext.allow do
        root_for_parent.record(RecordingStudio::Access, parent_recording: parent_recording) do |access|
          access.actor = user
          access.role = role
        end
      end
    end

    ensure_access_for.call(root_recording, :edit)
    ensure_access_for.call(accessible_root_recording, :edit)
    ensure_access_for.call(admin_root_recording, :admin)

    # Grant commenter edit access to Studio Workspace
    commenter_access_exists = RecordingStudio::Recording.unscoped
      .where(
        root_recording_id: root_recording.id,
        parent_recording_id: root_recording.id,
        recordable_type: "RecordingStudio::Access",
        trashed_at: nil
      )
      .order(created_at: :asc, id: :asc)
      .detect do |recording|
        access = recording.recordable
        access&.actor == commenter && access.role.to_s == "edit"
      end

    unless commenter_access_exists
      RecordingStudioAccessible::AccessCreationContext.allow do
        root_recording.record(RecordingStudio::Access, parent_recording: root_recording) do |access|
          access.actor = commenter
          access.role = :edit
        end
      end
    end
  end
ensure
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: commenter@commenter.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Workspace '#{accessible_workspace.name}' with root recording ##{accessible_root_recording.id}"
puts "Seeded: Workspace '#{private_workspace.name}' with root recording ##{private_root_recording.id}"
puts "Seeded: Folder '#{folder.name}' and page '#{page.title}'"
puts "Seeded: Sample notifications (root, global, optional-root)"
