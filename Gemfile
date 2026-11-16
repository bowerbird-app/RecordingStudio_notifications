# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_notifications.gemspec
gem "devise"
gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.377"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v7.3.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.45.1"
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v1.2.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.9.0"
# Query helpers for Accessible (engine not booted).
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v1.0.1",
                                  require: false
gem "view_component", "4.19.0"

gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.4.0"
  gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.0"
  gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v6.0.0"
  gem "redis", "~> 5.3"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", "~> 1.81.7", require: false
  gem "rubocop-rails", require: false
end
