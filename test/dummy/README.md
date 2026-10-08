# Dummy App

This Rails app exists to validate Recording Studio Notifications in a real host application.

## What It Covers

- Devise authentication with a seeded admin user
- `Current.actor` wiring for Recording Studio events
- Root workspace plus seeded folder and page recordables
- Seeded inbox mix: mentions, approvals, comments, new pages, workspace changes, and system announcements, read and unread, with different icons
- FlatPack layout integration and Tailwind source scanning
- Dummy-only English and French via Recording Studio Internationalization, with a compact language selector in the top nav
- Mounted `RecordingStudio::Engine` route behavior inside a host app
- A starter sidebar menu and companion docs pages for gem-specific onboarding

## Quick Start

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/dev
```

Run the commands above from the dummy app directory, not the repository root.

Dummy credentials (`config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

Then open the app and sign in with:

- Email: `admin@admin.com`
- Password: `Password`

## Useful Routes

- `/` - dummy app home page and template guidance
- `/recording_studio` - redirects to `/` while the mounted Recording Studio engine stays available under that prefix for non-root routes
- `/users/sign_in` - Devise sign-in page
- `/docs/install`, `/docs/config`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, `/docs/methods` - starter sidebar pages to adapt for the gem
- `/up` - Rails health check
- Language selector in the top nav switches dummy between English and French (`/recording_studio_internationalization/locale`). French copy lives in dummy `config/locales/fr.yml`, not the engine.

## Why This App Exists

Use this app to verify the generated addon experience before renaming the gem or copying patterns into another host app. If a layout, route, asset source, or Recording Studio initializer change breaks here, the template likely needs adjustment before reuse.

The authenticated layout in `app/views/layouts/flat_pack_sidebar.html.erb` and sidebar menu in `app/views/layouts/flat_pack/_sidebar.html.erb` are a styled skeleton, not the final information architecture for every addon. Replace the sidebar items and docs page content so they match the gem's actual concepts and workflows.

Likewise, the home page in `app/views/home/index.html.erb` should stay a minimal demo surface for the gem's core feature. Do not turn it into a wall of documentation; the dedicated sidebar pages exist so deeper explanations can live in focused sections.
