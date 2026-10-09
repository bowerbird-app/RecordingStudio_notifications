# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_notifications.gemspec
gem "devise"
gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.207"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.4.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.13.0"

gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
