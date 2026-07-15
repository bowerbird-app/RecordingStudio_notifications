> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/recording_studio_notifications](https://github.com/bowerbird-app/recording_studio_notifications/tree/main/docs/recording_studio_notifications)
> *   **Last Updated:** May 5, 2026
>
> *Maintainers: Please update the date above when modifying this file.*

---

# Local Development Setup

This guide covers setting up the gem for local development outside of GitHub Codespaces.

---

## Prerequisites

| Dependency | Version | Notes |
|------------|---------|-------|
| Ruby | 3.3+ | Check with `ruby -v` |
| PostgreSQL | 16+ | UUID support required |
| Redis | 7+ | For Action Cable / caching |
| Node.js | 18+ | For TailwindCSS CLI (optional if using standalone) |

---

## Setup Steps

### 1. Clone the Repository

```bash
git clone https://github.com/bowerbird-app/RecordingStudio_recording_studio_notifications.git
cd RecordingStudio_recording_studio_notifications
```

### 2. Install Gem Dependencies

```bash
bundle install
```

### 3. Setup the Dummy App

```bash
cd test/dummy
bundle install
```

### 4. Configure Database

Edit `test/dummy/config/database.yml` if your PostgreSQL setup differs from defaults:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  port: <%= ENV.fetch("DB_PORT", 5432) %>
```

Edit the username and password too if your local PostgreSQL credentials differ:

```yaml
  username: <%= ENV.fetch("DB_USER", "postgres") %>
  password: <%= ENV.fetch("DB_PASSWORD", "postgres") %>
```

Or export environment variables:

```bash
export DB_HOST=localhost
export DB_USER=your_user
export DB_PASSWORD=your_password
```

### 5. Prepare the Database

```bash
cd test/dummy
bin/rails db:prepare
```

This creates the database, runs migrations (including enabling `pgcrypto` for UUIDs), and seeds data.

### 6. Build TailwindCSS

```bash
bin/rails tailwindcss:build
```

### 7. Start the Development Server

```bash
bin/dev
```

This runs both the Rails server and Tailwind watcher via Foreman.

Alternatively, run just the Rails server:

```bash
bin/rails server
```

### 8. Visit the App

Open http://localhost:3000

### 9. Run Tests

```bash
cd ..
bundle exec rake test
```

---

## Common Tasks

### Run Tests

```bash
# From the gem root
bundle exec rake test
```

### Run RuboCop

```bash
bundle exec rubocop
```

### Rebuild Tailwind

```bash
cd test/dummy
bin/rails tailwindcss:build
```

### Reset Database

```bash
cd test/dummy
bin/rails db:reset
```

### Add a Migration

```bash
cd test/dummy
bin/rails generate migration AddFieldToModel field:type
bin/rails db:migrate
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `postgres` | PostgreSQL username |
| `DB_PASSWORD` | `postgres` | PostgreSQL password |
| `DB_NAME` | `app_development` | Database name |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection URL |
| `PORT` | `3000` | Rails server port |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `PG::ConnectionBad` | Ensure PostgreSQL is running and credentials are correct. |
| `relation does not exist` | Run `bin/rails db:prepare` to create tables. |
| Tailwind styles missing | Run `bin/rails tailwindcss:build`. |
| Port 3000 in use | Use `PORT=3001 bin/dev`. |
| Redis connection refused | Start Redis: `redis-server` or `brew services start redis`. |
| Bundle install fails | Check Ruby version matches `.ruby-version` (3.3.0). |

---

## Project Structure

```
recording_studio_notifications/
├── app/                      # Engine application code
│   ├── controllers/recording_studio_notifications/
│   └── views/recording_studio_notifications/
├── config/
│   └── routes.rb             # Engine routes
├── lib/
│   ├── recording_studio_notifications.rb       # Main entry point
│   ├── recording_studio_notifications/
│   │   ├── configuration.rb  # Configuration API
│   │   ├── engine.rb         # Engine definition
│   │   └── version.rb
│   └── generators/           # Install generator
├── test/
│   ├── dummy/                # Test Rails application
│   └── *_test.rb             # Unit tests
├── docs/                     # Documentation
├── Gemfile
├── Rakefile
└── recording_studio_notifications.gemspec
```

---

## Next Steps

- [Rename the gem](RENAMING.md) to your own name
- [Configure the gem](CONFIGURATION.md) with your settings
- [Understand Tailwind setup](CSS_JS_ASSETS_ARCHITECTURE.md)
- [Install in a host app](INSTALLING.md)

---

Happy hacking! 💻
