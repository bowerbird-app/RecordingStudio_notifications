# frozen_string_literal: true

require_relative "lib/recording_studio_notifications/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_notifications"
  spec.version     = RecordingStudioNotifications::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_notifications"
  spec.summary     = "Recording Studio notifications addon"
  spec.description = "A Recording Studio addon that delivers idempotent, root-aware notifications " \
                     "through registered channels with an in-app adapter."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_notifications"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_notifications/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio"
  spec.add_dependency "recording_studio_accessible"
  spec.add_dependency "flat_pack"
  spec.add_dependency "view_component"
end
