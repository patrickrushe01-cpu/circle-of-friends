# Circle of Friends — Design Document

## 1. Concept

Circle of Friends visualizes a person's ten closest relationships as a radar
screen. Contacts appear as avatars on concentric rings; distance from the
center reflects how frequently the user has interacted with them recently.
The radar recalculates every hour and drifts over time as real behavior
changes. **Quality is explicitly out of scope for v1 — this is a frequency
instrument, not a sentiment one.**

## 2. Platform Reality (this drives the whole architecture)

| Signal | Android | iOS |
|---|---|---|
| Call log | Direct read via `CallLog` content provider (permission) | Not accessible to third-party apps — hard OS restriction |
| SMS frequency | Direct read via `Telephony.Sms` content provider (permission) | Not accessible to third-party apps — hard OS restriction |
| Calendar meetings | `device_calendar` plugin (cross-platform) | `device_calendar` plugin (cross-platform, via EventKit) |
| Email frequency | IMAP/OAuth connection, counted app-side | IMAP/OAuth connection, counted app-side |
| Manual check-in | Always available | Always available |

Because iOS permanently lacks call/SMS access, the two platforms **cannot**
share a single signal set. The architecture treats call/SMS as an
**Android-only bonus signal layered on top of** a cross-platform baseline
(calendar + email + manual check-in) that works identically everywhere. This
means:

- iOS users' scores are necessarily sparser and lean harder on check-ins —
  the UI should nudge check-ins more assertively on iOS.
- The scoring service takes a per-platform *available signal set* and
  normalizes weights across whatever signals actually exist for that install,
  so an iOS-only user isn't structurally penalized against an Android user
  for a data source their OS blocks.
- No feature may assume call/SMS exist. The Android module is additive, never
  load-bearing.

## 3. App Architecture

Four areas, matching the brief:

1. **Onboarding** (`lib/screens/onboarding/`) — runs once. Contact selection
   (exactly ten), then permission requests (calendar + email always; call
   log + SMS additionally on Android).
2. **Radar home** (`lib/screens/radar/`) — the core screen. Custom-painted
   concentric rings, avatars positioned by current ring + score, tap to see
   an interaction history sheet. Recalculates hourly via a background job;
   animates between the previous and current ring on each recompute.
3. **Check-in flow** (`lib/screens/checkin/`) — a modal sheet triggered by a
   local notification (or opened manually from the radar). Tap names from
   the tracked ten, tap an interaction type. No typing.
4. **Settings** (`lib/screens/settings/`) — manage the tracked ten (swap a
   contact out, subject to the fixed-ten rule — see §7), review/re-grant
   permissions, notification frequency, data export/reset.

Shared layers underneath all four:

- `lib/models/` — plain data classes for Contact, Interaction, Score.
- `lib/database/` — Isar (on-device, no server sync) persistence.
- `lib/services/` — scoring engine, permission orchestration, notification
  scheduling, hourly recompute job, and per-platform data collectors.
- `lib/platform/` — the Dart-side MethodChannel client for the Android
  native module.

## 4. Technical Stack

- **Flutter** (Dart) for all UI and shared logic, both platforms.
- **Kotlin native module** (`android/`) exposed via `MethodChannel`, reading
  `CallLog.Calls` and `Telephony.Sms` content providers directly — no
  network calls, no server round-trip.
- **`device_calendar`** plugin for calendar meetings with tracked contacts
  (cross-platform, backed by EventKit on iOS / CalendarContract on Android).
- **Email frequency**: OAuth-connected IMAP/Gmail-API polling, counted
  on-device; only aggregate counts are persisted, never message content.
- **Isar** as the local database — schema-typed, fast, pure-Dart queries,
  no native SQL required, and it plays well with reactive `watch()` streams
  which the radar screen uses to animate on recompute.
- **`workmanager`** (Android) / `BGTaskScheduler` via `flutter_background_fetch`
  (iOS) for the hourly recompute — each OS's own constrained background
  execution model, not a custom scheduler.
- **`flutter_local_notifications`** for the check-in prompts — entirely
  on-device, no push infrastructure needed since there's no server.

Everything stays on-device. There is no backend; this is a deliberate
constraint from the brief (no server sync) and it simplifies privacy review
enormously — nothing about who you call or when ever leaves the phone.

## 5. Data Schema

### `contacts`
| field | type | notes |
|---|---|---|
| id | int (autoIncrement) | Isar id |
| deviceContactId | String | stable link back to the OS address book entry |
| name | String | display name, cached at add-time |
| avatarRef | String? | cached avatar path/bytes reference |
| dateAdded | DateTime | when it entered the tracked ten |
| active | bool | false if removed from the ten (soft-delete, keeps history) |

### `interactions`
| field | type | notes |
|---|---|---|
| id | int (autoIncrement) | Isar id |
| contactId | int | FK → contacts.id |
| timestamp | DateTime | when the interaction occurred |
| source | enum | `call`, `text`, `calendar`, `email`, `manual` |
| type | enum? | for manual check-ins: `call`, `text`, `inPerson`, `other` |
| durationSeconds | int? | calls/meetings only, null otherwise |

### `scores`
| field | type | notes |
|---|---|---|
| id | int (autoIncrement) | Isar id |
| contactId | int | FK → contacts.id |
| computedAt | DateTime | the hourly tick this row belongs to |
| rawScore | double | decayed, weighted sum for that tick |
| rank | int | 1 (closest) – 10, among the ten that tick |
| ring | int | 0 (innermost) – outer bucket index |

`scores` is append-only — one row per contact per hourly tick — which is
what makes the ring-transition animation on the radar possible: the UI reads
the last two ticks per contact and tweens between them.

## 6. Scoring Logic

Every hour, for each of the ten tracked contacts:

1. **Pull** all `interactions` for that contact from the trailing 14 days.
2. **Weight** each interaction by an exponential recency decay —
   `weight = source_weight * exp(-λ * age_hours)` — so a call yesterday
   outweighs three calls two weeks ago, but old activity doesn't vanish to
   zero, it fades. `λ` is tuned so a 14-day-old interaction contributes
   roughly 10% of a same-day one.
3. **Source weights** are normalized across whatever signals exist on this
   install. Baseline (both platforms): manual check-in = 1.0, calendar
   meeting = 1.0 (meetings imply real time spent), email = 0.4 (weak
   signal, easy to send without real closeness). Android-only addition:
   call = 1.0, text = 0.5. When call/SMS are absent (iOS), weights are
   re-normalized so the remaining signals aren't structurally
   under-weighted relative to an Android install — see §2.
4. **Sum** the weighted values into one `rawScore` per contact.
5. **Rank** the ten contacts by `rawScore`, descending.
6. **Bucket** into rings: ring 0 (innermost) gets the top-scoring contacts,
   with ring boundaries either fixed-size (e.g. rings of 2/3/3/2) or
   score-gap-based (a ring break wherever the score drop between
   consecutive ranks exceeds a threshold) — fixed-size is the v1 default
   for predictable, readable visuals; gap-based is a v1.1 candidate once
   real score distributions are observed.
7. **Persist** one `scores` row per contact for this tick.

This runs identically on both platforms — the platform difference lives
entirely in *what interactions exist to pull*, not in the scoring math.

## 7. The Fixed Ten, and Changing It

The brief states the ten are "fixed" at onboarding. In practice users will
want to swap someone out (a relationship ends, a new close friend appears).
v1 supports this from Settings as a deliberate, infrequent action — not a
casual edit — because arbitrary churn would make the historical `scores`
trend meaningless. Swapping a contact soft-deletes the old one (`active =
false`, history retained for later reference) and inserts the new one with
`dateAdded = now`; the radar's trend animation naturally shows the new
contact starting with no history.

## 8. Screen-by-Screen

**Onboarding**
1. Address-book picker, multi-select exactly 10 (disabled state past 10,
   counter "7 of 10 selected").
2. Permission requests, presented as a short sequence with a one-line reason
   for each ("Calendar access lets us see meetings with your circle"), not
   a blind OS dialog.
3. Hand off to the radar screen, empty state ("Your radar fills in as you
   interact — check back in an hour, or log a catch-up now").

**Radar home**
- Full-screen circular canvas, concentric ring guides, center marked as
  "you." Avatars placed on their ring, angularly distributed to avoid
  overlap (deterministic per contact, e.g. hashed angle, so a given
  contact doesn't jitter position between ticks unless it changes rings).
- Tap an avatar → bottom sheet: recent interaction timeline, current
  streak/gap ("last in touch 3 days ago").
- Pull-to-refresh forces an out-of-cycle recompute (useful right after
  logging a check-in).
- A subtle "last updated Xm ago" label — the radar is explicitly not
  real-time, and the UI should not pretend it is.

**Check-in flow**
- Triggered by a local notification 1–2x/day ("Catch up with anyone
  today?"). Tapping it opens the modal directly.
- Modal: grid of the ten contact avatars/names, tap one or more, then tap
  an interaction type chip (Call / Text / In person / Other). No text
  entry. Multiple contacts can be logged in one pass before dismissing.
- Also reachable manually from the radar (floating action button) for
  logging a catch-up the notification didn't happen to catch.

**Settings**
- The tracked ten, with a "swap" affordance per contact (see §7).
- Permission status per source, with a re-request/deep-link-to-OS-settings
  action for anything denied.
- Notification frequency and quiet hours.
- Data reset (clears local DB) and data export (dumps interactions/scores
  as JSON — since there's no server, this is the only way to back up).

## 9. Phased Build Plan

**Phase 1 — skeleton & data layer**
Flutter project scaffold, Isar schema, models, manual check-in flow only
(no permissions yet). This alone is a usable, testable app: a diary of
manual check-ins driving a real radar. Validates the scoring math and the
radar visualization before touching platform permissions.

**Phase 2 — cross-platform signals**
Calendar integration via `device_calendar`, email frequency via IMAP/OAuth.
Now iOS is feature-complete for v1.

**Phase 3 — Android native module**
Kotlin `CallLogSmsReader`, `MethodChannel` plumbing, permission requests,
merge into the scoring input set. Android now has richer signal than iOS —
expected, per §2.

**Phase 4 — polish**
Hourly background scheduling on both OSes, ring-transition animation,
notification tuning, settings screen completeness, data export.

**Phase 5 — store readiness**
App icons/splash, privacy policy (critical given call/SMS/calendar/email
access — required by both stores' data-safety disclosures), TestFlight +
Play internal testing, then submission.

## 10. Privacy Posture

Because everything is on-device with no server, the privacy story is
unusually clean, but store review will still scrutinize call/SMS access
heavily on Android (Google's Play policy restricts call-log/SMS permissions
to apps whose *core* function requires them — a relationship radar plausibly
qualifies, but the Play Console declaration form and an in-app disclosure
should be prepared before submission, not after a rejection). Only
aggregate frequency/timestamps are ever stored — message and call content
are never read beyond what the content provider query itself needs
(number/contact id, timestamp, duration), and email is polled for
send/receive counts only, never body content.

## 11. Setup & Registration Checklist

- Flutter SDK + toolchain — free.
- Apple Developer Program — ~$99/yr, required for physical-device testing
  and App Store submission.
- Google Play Console — one-time $25, only needed at publish time; local
  Android testing is free.
- Claude Code (or equivalent) subscription to generate/maintain the Flutter
  and Kotlin code from this brief.
- OAuth app registrations for email access (Google/Microsoft) — needed
  before Phase 2 email integration can be tested end-to-end.
