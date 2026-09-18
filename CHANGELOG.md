# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.2] - 2026-09-18

### Changed
- Inbox Clear all and Settings are FlatPack default buttons instead of text links.
- Inbox content width is `max-w-3xl` on desktop so the list does not stretch edge to edge.
- Admin All notifications table sits in a FlatPack outlined card inside a 2-column grid so the table has a border and does not span the full desktop width.

### Fixed
- Dummy Tailwind `@source` globs now include Cloud Agent gem installs under `/usr/local/lib/ruby/gems`, so FlatPack utilities compile.
- Dummy `application` and `admin` layouts always include `tailwind.css` and drop the leftover `mt-28` scaffold wrapper.

### Upgrade notes
- If you overrode `app/views/recording_studio_notifications/notifications/_title.html.erb`, switch Clear all and Settings to `FlatPack::Button::Component` with `style: :default`.
- If you overrode the inbox index template, keep the list at `max-w-3xl` (was `max-w-5xl`).
- If you overrode Recording Studio Admin `screens/_table_frame.html.erb` or `screens/_table_placeholder.html.erb`, keep the notifications screen (`recording_studio_notifications_all_notifications`) wrapped in `FlatPack::Grid::Component` (`cols: 2`) around `FlatPack::Card::Component` (`style: :outlined`).
- Dummy/host Tailwind configs that only scan `vendor/bundle` and `/usr/local/bundle` should also scan `Bundler.bundle_path` (Cloud Agents: `/usr/local/lib/ruby/gems/*/bundler/gems`), then run `bin/rails tailwindcss:build`.

## [0.3.1] - 2026-09-02

Cloud Agent install no longer fails a warm environment rebuild. Skills still
fetch at Build.

### Added
- Cloud Agent boot files: `.cursor/install.sh`, `.cursor/fetch-skills.sh`,
  `.cursor/start.sh`, and `.cursor/environment.json`. Builds fetch the skill
  pack instead of a vendored copy.

### Fixed
- `.cursor/install.sh` skips apt, ruby-build, db:prepare, and tailwind when
  Ruby, bundle, and Postgres are already usable. A skippable provision
  failure no longer fails the Build. Fetch-skills always runs last.

### Upgrade notes
- No host or schema changes. Rebuild the Cloud Agent environment with Draft
  off so Build loads the pack.

## [0.3.0] - 2026-09-01

### Added
- Delivery payload resolver API: `register_delivery_payload_resolver` and `delivery_payload_for`. Resolved output is transient and is never persisted on the notification or delivery.
- Optional `available_for?(recipient:, notification: nil, delivery: nil)` on channel adapters. Inapplicable optional channels are skipped; inapplicable required channels raise.

### Changed
- README adapter docs now describe `available_for?` and delivery payload resolvers for sensitive content such as OTP codes.

### Upgrade notes
- Adapters may implement `available_for?(recipient:, notification: nil, delivery: nil)`. Optional channels are skipped when not applicable; required channels that are not applicable raise an error.
- Sensitive content (for example OTP codes) must not be stored in persisted `title`, `body`, or `metadata`. Register a delivery payload resolver instead; email and push adapters should call `delivery_payload_for` at send time. Notification types without a resolver continue to use the stored `title`, `body`, and `url`.

## [0.2.6] - 2026-08-31

### Fixed
- Required channel pills on notification settings no longer show "(required)" or a remove control; hovering shows a tooltip explaining the channel cannot be removed.
- Required channels no longer appear in the notification settings channel dropdown list; they stay visible as non-removable pills in the select. When a type has no optional channels the whole channel select is disabled rather than hidden.
- Corrected Tailwind `@source` paths for `app/assets/tailwind/application.css` so they resolve from Rails.root (`../../../vendor/bundle/...`) and match git-gem folder names (`flatpack-*`, `recording_studio_notifications-*`).
- Updated the dummy app Tailwind sources so FlatPack components and Recording Studio gem views are scanned during `tailwindcss:build`.

### Changed
- Installed `recording_studio_notifications_email` in the dummy app and exposed `email` as an optional channel on its notification types.

### Upgrade notes
- If your host Tailwind entry still uses the old install-generator lines (`../../vendor/bundle/**/flatpack/...` or `**/recording_studio_notifications/...` without a `-*` suffix), replace them with the paths from `rails generate recording_studio_notifications:install` (or the README), then run `bin/rails tailwindcss:build`.
- Prefer `bundle config set --local path vendor/bundle` (or an equivalent Bundler path that the `@source` globs cover) so Tailwind can see gem templates.

## [0.2.5] - 2026-07-24

### Fixed
- Removed grouped notification accordion border bleed in FlatPack versions that render item border wrappers at deeper selector depth.
- Finalized dummy seeded cadence rollups during seeding so grouped in-app notifications are immediately visible in demo inbox/menu views.

## [0.2.4] - 2026-07-21

### Fixed
- Deferred grouped cadence delivery for all channels, including `:in_app`, when rollups are enabled.
- Hid pending in-app rollup notifications from inbox/menu until the cadence period closes and rollup delivery completes.
- Removed persistent accordion item borders in grouped notification rows to keep list styling consistent.

### Changed
- Updated cadence docs and dummy app cadence coverage to reflect deferred in-app rollup behavior.

## [0.2.3] - 2026-07-17

### Fixed
- Scoped notification menu and /notifications inbox visibility to the current root plus rootless notifications, excluding notifications from other workspace roots.

## [0.2.2] - 2026-07-17

### Fixed
- Restored async notification-menu polling by correcting namespaced Stimulus data attribute keys in the menu helper.

## [0.2.1] - 2026-07-17

### Changed
- Updated FlatPack to `v0.1.127`.
- Removed the extra content padding from grouped notification accordions.

## [0.2.0] - 2026-07-15

### Added
- A cleared notification state and a Clear all action for unread inbox items.
- Unread notification counts on inbox groups.

### Changed
- Notification settings now group types by category and present channel and frequency controls side by side.
- Required channels and required cadences are shown as disabled controls with their selected values visible.

### Removed
- The abandoned notification cadence and digest implementation, including its database tables, scheduler, settings, seed data, and documentation. Notifications now use the standard immediate delivery path.

## [0.1.1] - 2026-04-28

### Changed
- Bumped the dummy app FlatPack dependency from `0.1.2` to `0.1.33` and pinned it by tag in `test/dummy/Gemfile`

## [0.1.0] - 2025-12-04

### Added
- Initial release
- Rails mountable engine structure
- PostgreSQL with UUID primary keys support
- TailwindCSS v4 integration
- GitHub Codespaces devcontainer configuration
- Docker Compose setup with PostgreSQL and Redis
- Install generator for host applications
- Comprehensive README and documentation
- Basic test suite with Minitest

[Unreleased]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.1
[0.1.0]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.0
