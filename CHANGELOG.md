# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

## [0.12.0] - 2026-10-19

### Added
- Admin hub widget and screen for `notification_deliveries.failed_by_channel_over_time`. The compact chart on All notifications links to a site-scoped screen. The screen lists stored failed `Delivery` rows (time, recipient, channel, error) with date-range, channel, and kind filters. The chart still reads `RecordingStudioMetrics.execute` with `group_by=channel`. Admin stays optional.

### Fixed
- Failed-deliveries widget and screen charts send `{ x:, y: }` points (numeric `y`) so ApexCharts can draw. Tuple `[date, value]` points had string dates coerced to numbers, so every point landed at x=0.

### Upgrade notes
- Bump to `0.12.0`. No migration. No host code change when Admin is already mounted and `all_notifications` is enabled.
- Hosts without `recording_studio_admin` are unchanged. The gem still does not depend on that gem.
- Site-scoped Admin cards need `site_admin_recording_resolver` to return the same recording as `access_recording_resolver`.

## [0.11.0] - 2026-10-19

### Changed
- Requires `flat_pack` `~> 0.1.254`. Development and dummy Gemfiles pin tag `v0.1.254`.
- The inbox card uses `style: :default` and `border: :strong`. That is the 0.1.237 colour-style API for the old outlined card (surface fill, 2px border).

### Upgrade notes
- Bump to `0.11.0`. No migration.
- Hosts on this version need Flatpack `~> 0.1.254` (git tag `v0.1.254`), Accessible `>= 0.20.0`, and Admin `>= 2.4.0`.
- Move a host card that still uses `style: :outlined` to `style: :default, border: :strong`.
- No compatibility shim.

## [0.10.0] - 2026-10-17

### Added
- `inbox` on notifications (boolean, default `true`). Register a type with `inbox:`, or pass `inbox:` to `notify`, to keep the row and its non-in-app deliveries out of the inbox. `inbox: false` skips the `:in_app` delivery. Index, menu, group page, unread count, and clear-all use the `in_inbox` scope. `show` and the other member actions return 404 for a hidden row. `open` still marks it read and redirects. Admin and the sent and read-vs-unread metrics still count it. A retry with the same idempotency key keeps the first `inbox` flag.
- Public unsubscribe. `RecordingStudioNotifications.unsubscribe_url` and `list_unsubscribe_headers` build an absolute signed link whose purpose is that notification type and channel. GET confirms and writes nothing. The form POST turns the optional channel off and redirects to the done page. A POST body of `List-Unsubscribe=One-Click` turns it off and returns 200. Tokens expire after `unsubscribe_expires_in` (default 1 year).
- `Delivery#mark_email_unsubscribed!(at:)`, `mark_email_bounced!(at:)`, `mark_email_opened!(at:)`, `mark_email_clicked!(at:)`, and `mark_email_complained!(at:)`. Each stores its timestamp in delivery metadata. Unsubscribe also turns that type's email preference off. A bounce does not change delivery status.

### Upgrade notes
- Bump to `0.10.0`.
- Run `bin/rails generate recording_studio_notifications:migrations` and `bin/rails db:migrate`. The new migration adds `inbox` (boolean, null false, default true). Existing rows stay in the inbox.
- `notify` and notification type registration accept `inbox:`. `inbox: false` with a required `:in_app` channel raises `ArgumentError` and writes nothing.
- Hosts that put the unsubscribe URL in mail set `default_url_options` (the same host mailers already need) so the link is absolute.
- No compatibility shim.

## [0.9.1] - 2026-10-17

Test and repo cleanup. Notification behavior is unchanged.

### Changed
- Gem and dummy suites now collate SimpleCov, tracking `app/` and `lib/`. `rake test:all` prints that combined result. `coverage/` and `test/dummy/coverage/` are no longer committed.

### Removed
- Stale template notes: `MIGRATION_NOTES.md`, `UPDATE_SUMMARY.md`, and `docs/recording_studio_notifications/GEM_TEMPLATE_README.md`, `PRIVATE_GEMS.md`, and `SERVICES.md`.

### Upgrade notes
- Bump to `0.9.1`. No migration. No host changes.

## [0.9.0] - 2026-10-16

### Added
- Optional `visible_to:` on `NotificationTypeRegistry.register`. Pass a proc that receives the settings recipient, or omit it (`nil`) so every recipient sees the type. The settings page and preference writes use the same filter.
- Default Accessible `:view` action. When the host has not defined `:view`, the engine registers it and checks `RecordingStudioAccessible.authorized?(actor:, recording:, role: :view)`. Host-defined `:view` is left alone.

### Changed
- Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4` so Metrics 0.3 discovery (`catalog_metadata`, `DiscoveryHandler`) stays on this major. This gem still does not call `RecordingStudioMetrics::Api.register!`. The host registers those endpoints once.
- `notify` with no selected channels returns `nil` and does not raise. A type with `required_channels: []` can be saved with None. Delivery then sends nothing.

### Upgrade notes
- Bump to `0.9.0`. No migration.
- Hosts that already define Accessible `:view` keep that policy.
- Hosts that never defined `:view` now show root-scoped notifications when the recipient has a view role on that root.
- Rescue of `ArgumentError` for an empty channel list is no longer needed. `notify` returns `nil`.
- Register staff-only kinds with `visible_to:` if members should not see them on settings.

## [0.8.0] - 2026-10-14

### Added
- `notification_deliveries.failed_by_channel_over_time` (timeseries, unit `count`): failed deliveries by `updated_at`, with `from` / `to` / `interval` and `group_by=channel`. Same site scope, `:operations` exposure and AdminRoot `:view` check as the other delivery metrics. No migration.

### Changed
- Requires `recording_studio_metrics` `>= 0.3.0, < 0.4`; development and dummy Gemfiles pin tag `v0.3.1`.

## [0.7.0] - 2026-10-13

Non-view Notifications copy joins customer and Admin chrome under
`recording_studio.notifications.*` so hosts can translate flashes, badge
overflow, and Admin chrome. English output stays the same as 0.6.0.

### Added

* English Rails I18n key for inbox badge overflow
  (`recording_studio.notifications.inbox.overflow`)
* Always-loaded dummy host override for the rarely shown
  `settings.required_channel_tooltip` key (boot-order guard)
* Locale regression: every `lib/**/*.rb` file must not mention
  `i18n.load_path` / `I18n.load_path`

### Changed

* Notification, Preference, and Delivery validation `errors.add` sites keep
  main’s English literals so DeliveryJob / RollupDeliveryJob `mark_failed!`
  still persists that exact English in `error_message` under any locale and
  when a host overrides English keys
* Group unread badge overflow (`9+`) resolves through `Copy.t` with English
  `default:`
* Controller flashes, settings help text, Admin chrome, and inbox grouping
  headings pass English `default:` on every `Copy.t` lookup
* Unit tests seed gem English via `store_translations` instead of appending
  `config/locales/en.yml` to `I18n.load_path`

### Upgrade notes

* Bump to `0.7.0`. No migration
* English hosts need no change. Copy new `inbox.overflow` into the host locale
  file when translating. Model validation messages are not I18n keys
* Hosts override by defining the same nested keys in their own `config/locales`
* Admin table column headers stay literal English. Dead
  `admin.all_notifications.columns.*` keys remain for host custom screens
* Accessible action labels and Metrics titles stay English at registration
* Do not add `RecordingStudio_Internationalization` as a dependency of this
  engine

## [0.6.0] - 2026-10-09

Site-wide Notifications metrics register with Recording Studio Metrics for the operations API.

### Added
- `RecordingStudioNotifications::Metrics.register!` registers `:notifications` and
  `:notification_deliveries` (`blast_radius: :site`) with RecordingStudioMetrics.
  Notifications: `notifications.sent_over_time` (`created_at`),
  `notifications.by_type` (`notification_type`), `notifications.read_vs_unread`
  (custom breakdown via `Notification.read` / `Notification.unread`).
  Deliveries: `notification_deliveries.by_status`, `notification_deliveries.by_channel`.
  Each metric is exposed on `:operations` only.
  `api_authorize` uses `RecordingStudioNotifications::Api::Access.can_view?`
  (AdminRoot `:view`, the same Accessible check Admin screens use).
  The admin root comes from `site_admin_recording_resolver`, then
  `access_recording_resolver`. If that resolver raises or returns nothing,
  the request is denied.
- Runtime dependency `recording_studio_metrics` `~> 0.2` (GitHub tag `v0.2.0`).

### Upgrade notes
- Bump to `0.6.0`. No migration.
- Add `recording_studio_metrics` at tag `v0.2.0`.
- This gem does not call `RecordingStudioMetrics::Api.register!`. When
  RecordingStudio API is present, the host registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

## [0.5.0] - 2026-10-09

Staff Admin chrome for All notifications joins the customer screens under
`recording_studio.notifications.*` so hosts can translate it.

### Added

* English Rails I18n keys for Admin All notifications screen and section
  (`recording_studio.notifications.admin.all_notifications.*` in
  `config/locales/en.yml`)

### Changed

* Admin screen/section title, subtitle, summary label, open-table link, and
  scope/status/empty-actor cell labels resolve through `Copy.t` (English
  output unchanged)
* Admin table column headers stay literal English (Admin DSL stores them as
  strings at class load; matching keys ship in `en.yml` for host overrides via
  a custom screen)

### Upgrade notes

* Bump to **0.5.0** (minor: hosts can translate Admin All notifications chrome).
  No migration
* English screens stay the same. Copy `recording_studio.notifications.admin.*`
  into the host locale file to override or add another language
* Customer menu/inbox/settings keys from **0.4.0** are unchanged
* Accessible action labels (`View notifications`, `Manage notification
  preferences`) stay English
* Do not add `RecordingStudio_Internationalization` as a dependency of this
  engine

## [0.4.0] - 2026-10-08

Customer-facing notifications copy now lives under `recording_studio.notifications.*` so hosts can translate the menu, inbox, settings, and flashes.

### Added
- Engine ships English only in `config/locales/en.yml`
- Nested keys: `t("recording_studio.notifications.menu.title")` (not a top-level `recording_studio_notifications:` namespace)
- Dummy hosts English and French via Recording Studio Internationalization, with a compact language selector in the top nav

### Upgrade notes
- Bump to **0.4.0** (minor: hosts can translate customer notification screens). No migration
- English screens stay the same. Component arguments that already accept custom text (`bell_label`, `empty_text` on the menu) still win, including `nil`
- To offer another language, copy `recording_studio.notifications.*` from `config/locales/en.yml` into the host (`config/locales/<locale>.yml`) and list that locale in `config.i18n.available_locales`. Dummy `test/dummy/config/locales/fr.yml` is a complete starting point
- Do not add `RecordingStudio_Internationalization` as a gem dependency of this engine. Use plain Rails I18n. Internationalization is a host (and dummy) concern
- Notification titles and bodies stored in the database are data written by other gems or people. This gem does not translate them
- Staff Admin screens (All notifications table) stay English

### Changed
- Development and dummy Gemfiles pin Recording Studio to GitHub tag `v4.2.2` (was `recording_studio/v3.0.0`).
- Gemspec requires `recording_studio`, `~> 4.2`.
- Companion pins required so Bundler can resolve Recording Studio 4.2: Accessible `v0.11.1`, Admin `v2.0.2`, Commentable `v0.3.1`, Root Switchable `v0.5.1`, notifications email `v0.3.2`, and dummy FlatPack `v0.1.129` (Admin 2.x floor).
- Development and dummy Gemfiles pin Accessible to GitHub tag `v0.11.1` (was `v0.10.1`).
- Dummy app copies Accessible 0.8–0.11 migrations: `depends_on_recording_id`, access invitations, and string `role`.
- Dummy seeds grant access through `bootstrap_owner_access!` and `grant_access` (Accessible 0.11 treats `RecordingStudio::Access` as readonly).

### Upgrade notes
- Point host and dummy Gemfiles at Recording Studio `v4.2.2` and Accessible `v0.11.1` (or newer with `recording_studio ~> 4.2`). Accessible `0.11` stores roles as strings and ships a migration; run `bin/rails generate recording_studio_accessible:migrations` then `bin/rails db:migrate` in hosts that use Accessible.
- Dummy hosts that use Admin 2.x need FlatPack `>= 0.1.129`.
- Dummy and host grants must use Accessible public services. Do not `update!` / `create!` `RecordingStudio::Access` rows.

## [0.3.2] - 2026-09-18

### Changed
- Inbox Clear all and Settings are FlatPack default buttons instead of text links.
- Inbox list sits in a FlatPack outlined card inside a 2-column grid so it has a border and does not span the full desktop width.
- Dummy seeds mix mentions, approvals, page comments, new pages, workspace changes, and system announcements, with both read and unread rows and distinct icons.

### Fixed
- Dummy Tailwind `@source` globs now include Cloud Agent gem installs under `/usr/local/lib/ruby/gems`, so FlatPack utilities compile.
- Dummy `application` and `admin` layouts always include `tailwind.css` and drop the leftover `mt-28` scaffold wrapper.
- Inbox card body uses FlatPack default padding (`:md`) so unread row shading no longer sits flush against the outlined border.

### Upgrade notes
- If you overrode `app/views/recording_studio_notifications/notifications/_title.html.erb`, switch Clear all and Settings to `FlatPack::Button::Component` with `style: :default`.
- If you overrode the inbox index template, wrap the list in `FlatPack::Grid::Component` (`cols: 2`) around `FlatPack::Card::Component` (`style: :outlined`) and keep the card body's default padding. Do not pass `padding: :none` on the filled list, and do not keep the old `max-w-3xl` / `max-w-5xl` width wrapper on the list.
- Dummy/host Tailwind configs that only scan `vendor/bundle` and `/usr/local/bundle` should also scan `Bundler.bundle_path` (Cloud Agents: `/usr/local/lib/ruby/gems/*/bundler/gems`; GitHub Actions Ruby: `/opt/hostedtoolcache/Ruby/*/x64/lib/ruby/gems/*/bundler/gems`), then run `bin/rails tailwindcss:build`.

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

[Unreleased]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.3.6...v0.4.0
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
