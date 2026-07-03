class Workspace < ApplicationRecord
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_recordable label: "Workspace", root: true
  recording_studio_accessible_children :access
end
