# frozen_string_literal: true

# Accessible, Metrics, Trashable, Commentable, Root Switchable, Cache,
# Internationalization, and Notifications Email still require
# recording_studio below 5. Widen that requirement when Bundler loads
# gemspecs so this app can resolve 6.1.0.
module WidenRecordingStudioRequirement
  def add_dependency(name, *requirements)
    widen = name.to_s == "recording_studio" && requirements.none? { |requirement| requirement.to_s.include?("6") }
    requirements = [">= 6.1.0"] if widen

    super
  end
end

Gem::Specification.prepend(WidenRecordingStudioRequirement) unless Gem::Specification.ancestors.include?(WidenRecordingStudioRequirement)
