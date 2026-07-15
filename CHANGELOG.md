# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.1
[0.1.0]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.0
