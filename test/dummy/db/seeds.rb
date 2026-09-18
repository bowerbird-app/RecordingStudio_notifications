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

private_user = User.find_or_create_by!(email: "private@private.com") do |u|
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
  page_url = "/pages/#{page.id}"

  seed_keys = []
  seed_notification = lambda do |attrs|
    key = attrs.fetch(:key)
    seed_keys << key
    notification = RecordingStudioNotifications.notify(
      notification_type: attrs.fetch(:type),
      recipient: attrs.fetch(:recipient),
      actor: attrs[:actor] || user,
      root_recording: attrs[:root_recording],
      recording: attrs[:recording],
      notifiable: attrs[:notifiable],
      title: attrs.fetch(:title),
      body: attrs[:body],
      url: attrs[:url],
      idempotency_key: key
    )
    notification.update!(
      title: attrs.fetch(:title),
      body: attrs[:body],
      url: attrs[:url],
      read_at: attrs[:read] ? (notification.read_at || Time.current) : nil,
      cleared_at: nil
    )
    notification
  end

  seed_notification.call(
    type: :workspace_change,
    recipient: user,
    root_recording: private_root_recording,
    recording: private_root_recording,
    title: "Private workspace changed",
    body: "This should be hidden by Accessible view filtering.",
    read: true,
    key: "seed-workspace-change-private-#{private_root_recording.id}"
  )

  inbox_roots = [
    { name: "studio", root: root_recording, recording: page_recording },
    { name: "client", root: accessible_root_recording, recording: accessible_root_recording }
  ]

  workspace_titles = [
    "Theme tokens got a quiet refresh",
    "Sidebar labels were shortened",
    "Default locale is English again",
    "Someone turned comments on",
    "Export format is CSV now",
    "Guest links expire after 7 days",
    "Trash empties after 30 days",
    "New cover images are allowed",
    "Folder order was shuffled",
    "Weekly digest moved to Mondays",
    "Two people joined as editors",
    "The brand kit was replaced",
    "Search indexes were rebuilt",
    "A stale invite was revoked",
    "Page templates picked up new blocks",
    "The home page default changed",
    "Billing contact was updated",
    "Timezone is Australia/Sydney",
    "API tokens were rotated",
    "A webhook endpoint was paused",
    "Custom domain DNS looks healthy",
    "Archive rules got stricter",
    "Slack alerts are off for now",
    "New cover colors landed"
  ]
  comment_titles = [
    "Jo left a note on Getting Started",
    "Sam poked a hole in the outline",
    "Riley asked about the launch date",
    "Jo wants a shorter intro",
    "Sam pasted a checklist",
    "Riley flagged a broken link",
    "Jo replied to Sam",
    "Sam added a screenshot",
    "Riley thinks the tone is stiff",
    "Jo moved a paragraph down",
    "Sam asked for an example",
    "Riley marked a typo",
    "Jo likes the new heading",
    "Sam wants a table here",
    "Riley dropped a question in the margin",
    "Jo resolved an old thread",
    "Sam quoted the brand kit",
    "Riley asked who owns this page",
    "Jo left a plus-one",
    "Sam wants the date in the title",
    "Riley tagged the legal bit",
    "Jo cleaned up a duplicate",
    "Sam asked for alt text",
    "Riley says ship it"
  ]
  page_titles = [
    "New page: Launch checklist",
    "New page: Pricing FAQ",
    "New page: Brand voice",
    "New page: Office hours",
    "New page: Support macros",
    "New page: Incident log",
    "New page: Q3 goals",
    "New page: Welcome script"
  ]
  approval_titles = [
    "Jo asked you to approve Launch checklist",
    "Pricing FAQ is waiting on you",
    "Sam sent Brand voice for review",
    "Riley needs a yes on Office hours"
  ]

  inbox_roots.each do |target|
    workspace_titles.each_with_index do |title, index|
      seed_notification.call(
        type: :workspace_change,
        recipient: user,
        root_recording: target[:root],
        recording: target[:root],
        title: title,
        body: "A workspace setting changed.",
        read: index.odd?,
        key: "seed-#{target[:name]}-workspace-update-#{index + 1}"
      )
    end

    comment_titles.each_with_index do |title, index|
      seed_notification.call(
        type: :page_comment,
        recipient: user,
        actor: index.even? ? commenter : user,
        root_recording: target[:root],
        recording: target[:recording],
        title: title,
        body: "A comment landed on Getting Started.",
        url: page_url,
        read: index.odd?,
        key: "seed-#{target[:name]}-page-comment-#{index + 1}"
      )
    end

    page_titles.each_with_index do |title, index|
      seed_notification.call(
        type: :page_created,
        recipient: user,
        actor: index.even? ? user : commenter,
        root_recording: target[:root],
        recording: target[:recording],
        title: title,
        body: "A page showed up in Product Docs.",
        url: page_url,
        read: index.odd?,
        key: "seed-#{target[:name]}-page-created-#{index + 1}"
      )
    end

    approval_titles.each_with_index do |title, index|
      seed_notification.call(
        type: :approval_requested,
        recipient: user,
        actor: index.even? ? commenter : user,
        root_recording: target[:root],
        recording: target[:recording],
        title: title,
        body: "A page is waiting for a yes.",
        url: page_url,
        read: index.odd?,
        key: "seed-#{target[:name]}-approval-#{index + 1}"
      )
    end
  end

  [
    "We'll be down tonight",
    "Password rules got a bit stricter",
    "Billing period starts Monday",
    "Two-factor is on for everyone now"
  ].each_with_index do |title, index|
    seed_notification.call(
      type: :system_announcement,
      recipient: user,
      title: title,
      body: "A global heads-up for everyone.",
      read: index.odd?,
      key: "seed-system-announcement-#{index + 1}"
    )
  end

  [
    "Jo mentioned you on Getting Started",
    "Sam pulled you into the outline",
    "Riley asked you about launch",
    "Jo tagged you on the pricing note"
  ].each_with_index do |title, index|
    seed_notification.call(
      type: :mention,
      recipient: user,
      actor: index.even? ? commenter : user,
      title: title,
      body: "Someone said your name on a page.",
      url: page_url,
      read: index.odd?,
      key: "seed-mention-#{index + 1}"
    )
  end

  # Newest rows: mix types, icons, and read state at the top of the default inbox.
  [
    { type: :workspace_change, title: "Client workspace updated", body: "Client Workspace preferences changed.",
      root_recording: accessible_root_recording, recording: accessible_root_recording, read: false,
      key: "seed-workspace-change-#{accessible_root_recording.id}" },
    { type: :workspace_change, title: "Workspace updated", body: "Studio Workspace settings changed.",
      root_recording: root_recording, recording: root_recording, read: false,
      key: "seed-workspace-change-#{root_recording.id}" },
    { type: :page_created, title: "New page: Getting Started", body: "The first page in Product Docs.",
      root_recording: accessible_root_recording, recording: accessible_root_recording, url: page_url, read: true,
      key: "seed-page-created-front" },
    { type: :page_comment, title: "Jo left a fresh note", body: "Latest comment on Getting Started.",
      actor: commenter, root_recording: accessible_root_recording, recording: accessible_root_recording,
      url: page_url, read: false, key: "seed-page-comment-front" },
    { type: :approval_requested, title: "Getting Started needs a yes", body: "Jo sent this page for review.",
      actor: commenter, root_recording: accessible_root_recording, recording: accessible_root_recording,
      url: page_url, read: true, key: "seed-approval-front" },
    { type: :system_announcement, title: "System maintenance", body: "Global announcement: maintenance window tonight.",
      read: false, key: "seed-system-announcement" },
    { type: :mention, title: "Riley mentioned you just now", body: "You're wanted on Getting Started.",
      actor: commenter, url: page_url, read: false, key: "seed-mention-front" }
  ].each do |attrs|
    seed_notification.call(attrs.merge(recipient: user))
  end

  RecordingStudioNotifications::Notification.where(recipient: user)
                                            .where("idempotency_key LIKE ?", "seed-%")
                                            .where.not(idempotency_key: seed_keys)
                                            .find_each(&:destroy!)

  # Finalize seeded cadence rollups so grouped in-app notifications are visible immediately.
  if RecordingStudioNotifications.configuration.rollup_delivery_enabled
    RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2099, 1, 1))
  end

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

    private_admin_exists = RecordingStudio::Recording.unscoped
      .where(
        root_recording_id: private_root_recording.id,
        parent_recording_id: private_root_recording.id,
        recordable_type: "RecordingStudio::Access",
        trashed_at: nil
      )
      .order(created_at: :asc, id: :asc)
      .detect do |recording|
        access = recording.recordable
        access&.actor == private_user && access.role.to_s == "admin"
      end

    unless private_admin_exists
      RecordingStudioAccessible::AccessCreationContext.allow do
        private_root_recording.record(RecordingStudio::Access, parent_recording: private_root_recording) do |access|
          access.actor = private_user
          access.role = :admin
        end
      end
    end
  end

ensure
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: commenter@commenter.com / Password"
puts "Seeded: private@private.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Workspace '#{accessible_workspace.name}' with root recording ##{accessible_root_recording.id}"
puts "Seeded: Workspace '#{private_workspace.name}' with root recording ##{private_root_recording.id}"
puts "Seeded: Folder '#{folder.name}' and page '#{page.title}'"
puts "Seeded: Mixed notification types (read and unread, distinct icons)"
