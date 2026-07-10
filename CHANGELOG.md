# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Configurable per-notification-type delivery cadences, durable digest collection, scheduled summary delivery, and digest detail pages.
- A development-only task and dummy seed data for exercising digest delivery locally.

### Changed
- Existing notification types retain immediate delivery through the default `:every_notification` cadence.
- Upgrades without the cadence-preference table temporarily retain immediate delivery and hide cadence controls until engine migrations run.

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

[Unreleased]: https://github.com/bowerbird-app/recording_studio_notifications/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.1
[0.1.0]: https://github.com/bowerbird-app/recording_studio_notifications/releases/tag/v0.1.0
