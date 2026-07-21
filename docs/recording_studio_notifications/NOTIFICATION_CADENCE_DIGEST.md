# Notification Cadence and Digest Delivery

## Goal

Notification cadence controls both:

1. **when** enabled channels deliver notifications; and
2. **how** those same source notifications are grouped in the in-app inbox.

Every notification remains an individual source record. A digest neither replaces nor merges source notifications in the database.

Use `:individual` for urgent notification types that must alert recipients immediately.

## Cadence Behavior

| Cadence | Source records | Outbound delivery | In-app inbox |
| --- | --- | --- | --- |
| `:individual` | Created immediately | One delivery per notification and channel immediately | Individual rows |
| `:daily` | Created immediately | One rollup per channel at each completed day | Daily collapsible group |
| `:every_other_day` | Created immediately | One rollup per channel at each completed two-day period | Two-day collapsible group |
| `:weekly` | Created immediately | One rollup per channel at each completed week | Weekly collapsible group |
| `:biweekly` | Created immediately | One rollup per channel at each completed two-week period | Biweekly collapsible group |
| `:monthly` | Created immediately | One rollup per channel at each completed month | Monthly collapsible group |

For example, a weekly `:page_comment` notification creates a source notification immediately but is included in the weekly rollup once its period closes. It does not send an immediate email, Slack message, push notification, or in-app alert.

## Phased Implementation

### Phase 1: Notification Type Cadence Configuration

Add these fields to each registered notification type:

```ruby
allowed_cadences: %i[individual daily weekly monthly],
default_cadence: :weekly,
required_cadence: nil
```

Rules:

1. `allowed_cadences` cannot be empty.
2. `default_cadence` must be in `allowed_cadences`.
3. `required_cadence`, when present, must be in `allowed_cadences`.
4. A saved recipient cadence override must be allowed for the type.

Resolve the effective cadence as:

```ruby
effective_cadence =
  type.required_cadence ||
  recipient_override ||
  type.default_cadence
```

Type registration creates no database rows. It defines the default applied to recipients without an override.

**Acceptance criteria**

- Type registration rejects invalid cadence configurations.
- Existing types default to `:individual` unless explicitly configured otherwise.
- `required_cadence` always wins over stored recipient preference.

### Phase 2: Preference Storage and API

Reuse the existing notification preferences table. Add a nullable `cadence` string column and allow `channel` and `enabled` to be nullable.

The table supports exactly two row shapes:

| Purpose | `channel` | `enabled` | `cadence` |
| --- | --- | --- | --- |
| Channel preference | Channel name | Boolean | `NULL` |
| Type-level cadence override | `NULL` | `NULL` | Cadence name |

Enforce this check constraint:

```sql
(
  channel IS NOT NULL
  AND enabled IS NOT NULL
  AND cadence IS NULL
)
OR
(
  channel IS NULL
  AND enabled IS NULL
  AND cadence IS NOT NULL
)
```

Add partial unique indexes:

1. One channel preference per recipient, type, and channel where `channel IS NOT NULL`.
2. One cadence override per recipient and type where `channel IS NULL`.

Keep APIs separate:

```ruby
# Delivery-channel preference
Preference.set!(
  recipient: user,
  notification_type: :page_comment,
  channel: :email,
  enabled: true
)

# Cadence preference
Preference.set_cadence!(
  recipient: user,
  notification_type: :page_comment,
  cadence: :daily
)

Preference.cadence_for(
  recipient: user,
  notification_type: :page_comment,
  default: :weekly
)
```

Behavior:

- No cadence row uses `default_cadence`.
- Saving a non-default cadence creates or updates the cadence row.
- Selecting the default cadence deletes the cadence row.
- Reading a preference never creates a row.
- A required cadence ignores stored overrides.

**Acceptance criteria**

- Channel rows and cadence rows cannot be mixed.
- Channel preferences never overwrite cadence preferences.
- Default selection removes the cadence override row.

### Phase 3: Inbox Grouping

Group active, visible source notifications using:

```text
recipient + notification type + effective cadence + local period
```

When root-specific separation is required, append the root recording to the key.

Use the recipient time zone when available, otherwise the application time zone.

| Cadence | Local period |
| --- | --- |
| `:individual` | No group wrapper |
| `:daily` | Midnight through next midnight |
| `:every_other_day` | Stable two-day period |
| `:weekly` | Monday midnight through next Monday |
| `:biweekly` | Stable Monday-based fourteen-day period |
| `:monthly` | First local day of month through first local day of next month |

Display rules:

- Full inbox uses type sections so mixed cadences remain understandable.
- The compact menu is a chronological feed of group cards and individual rows, ordered by newest contained notification.
- Expand the newest/current group in each section; keep older groups collapsed.
- A single-item period renders normally or with a compact period label, without a redundant collapse control.
- Do not split one group across pagination boundaries.
- Group wrappers are never persisted records.

**Acceptance criteria**

- Changing cadence immediately re-groups currently visible and historical source notifications.
- Group boundaries respect recipient-local dates and weeks.
- Per-notification authorization is enforced before rendering.

### Phase 4: Read and Archive Actions

A group has no persisted read state. Derive its state from contained source notifications.

```ruby
unread_count = notifications.count(&:unread?)
```

| Action | Result |
| --- | --- |
| Expand/collapse | No notification state changes |
| Open an item | Mark only that item read, then follow normal destination |
| Mark one item read/unread | Update only that item |
| Clear all | Set `cleared_at` for all visible unread items without changing `read_at` |
| Archive an item | Remove it from active inbox and update counts |

The global badge remains the total unread **source notification** count, not the number of groups.

**Acceptance criteria**

- A group header accurately reflects unread count after reads or archives.
- Cleared notifications render as read while retaining a blank `read_at` timestamp.
- Expanding or collapsing never changes delivery, archive, or read state.

### Phase 5: Immediate and Rollup Delivery Pipeline

The selected cadence applies to each enabled channel for that notification type.

| Channel | Individual cadence | Grouped cadence |
| --- | --- | --- |
| `:in_app` | One immediate in-app notification per source notification | One in-app rollup at period close |
| `:email` | One immediate email per source notification | One period rollup email |
| `:slack` | One immediate Slack send per source notification | One period rollup Slack send |
| `:push` | One immediate push per source notification | One rollup when supported by channel format |

A channel that cannot produce a useful rollup must provide its own rollup format or be unavailable for grouped cadences.

The rollup scope is:

```text
recipient + notification type + channel + cadence + period
```

Append root recording when root separation is required.

The existing deliveries table remains the delivery audit trail:

- `:individual`: one source notification produces one delivery row per enabled channel.
- Grouped cadence: every source notification still has one delivery row per enabled channel; related rows share a rollup key and represent one external send.

Store rollup information in delivery metadata:

```json
{
  "rollup": true,
  "rollup_key": "recipient/page_comment/email/weekly/2026-07-06",
  "cadence": "weekly",
  "period_starts_at": "2026-07-06T00:00:00Z",
  "period_ends_at": "2026-07-13T00:00:00Z"
}
```

**Acceptance criteria**

- Immediate types retain current one-notification-per-channel behavior.
- Grouped notifications create normal source and delivery records without immediate external dispatch.
- One completed period produces one rollup send per recipient/type/channel/period.

### Phase 6: Scheduler, Reservations, and Idempotency

Run a recurring job at cadence boundaries. For each closed period:

1. Find eligible source notifications.
2. Group by recipient, type, enabled channel, cadence, and period.
3. Reserve associated delivery rows transactionally using one deterministic `rollup_key`.
4. Send one rollup through the channel adapter.
5. Mark reserved rows delivered after provider acceptance.
6. Mark rows failed with error details when delivery fails.

Use `rollup_key` as the provider idempotency key where supported. Since external providers cannot share the database transaction, delivery is normally at-least-once. Provider idempotency is required for strong duplicate protection after a crash between external send and delivery-row update.

**Acceptance criteria**

- Concurrent scheduler runs cannot reserve the same pending delivery rows twice.
- Retries preserve the deterministic rollup key.
- Failed rollups remain auditable and retryable.

### Phase 7: Settings UI and Documentation

For notification types without `required_cadence`, show a **Notification cadence** selector only when more than one cadence is allowed.

Help text:

> Controls when this notification type is delivered and how it is grouped in your inbox.

For grouped values, make the outcome explicit:

> Weekly: receive one weekly rollup through enabled channels and view the week's notifications as an expandable inbox group.

For required cadence, display a non-editable explanation, for example:

> Notification cadence: Weekly. This cadence is required for page comments.

**Acceptance criteria**

- Users can only select allowed cadence values.
- Required cadence is visible but cannot be changed.
- Existing delivery and type-registration documentation is updated to distinguish immediate and rollup delivery.

### Phase 8: Regression Coverage and Rollout

Add focused coverage for:

- Type cadence validation and effective-cadence precedence.
- Preference-row constraints, uniqueness, and no-write reads.
- Time-zone-aware period calculation for every cadence.
- Mixed-cadence inbox and menu ordering.
- Per-item authorization and group bulk-action visibility.
- Individual versus grouped delivery creation.
- Scheduler reservation, retry, and duplicate-protection behavior.
- Required-cadence settings presentation.

Roll out in this order:

1. Ship schema and configuration support with `:individual` defaults.
2. Ship preferences and inbox grouping.
3. Ship scheduled rollup delivery behind the `rollup_delivery_enabled` configuration flag.
4. Enable grouped external channels only after adapters provide verified `deliver_rollup` formats and idempotency behavior.
