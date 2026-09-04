import 'dart:io';

import '../database/app_database.dart';
import '../models/interaction.dart';
import 'call_sms_channel.dart';

/// Bridges raw Android call/SMS events into the shared `interactions`
/// table. This is the only place that knows the Android module exists —
/// everything downstream (scoring, radar, check-in) is platform-agnostic,
/// per DESIGN.md §2's "additive, never load-bearing" rule.
class AndroidInteractionCollector {
  AndroidInteractionCollector(
    this._database, {
    CallSmsChannel channel = const CallSmsChannel(),
  }) : _channel = channel;

  final AppDatabase _database;
  final CallSmsChannel _channel;

  /// Pulls new events for every tracked contact and writes them into
  /// `interactions`. No-op on iOS. Intended to run right before each
  /// scoring tick (see [RecomputeScheduler]).
  Future<void> syncSinceLastRun() async {
    if (!Platform.isAndroid) return;

    final contacts = await _database.trackedContacts();
    if (contacts.isEmpty) return;

    // Trailing 14 days is enough — anything older has already aged out of
    // the scoring window (DESIGN.md §6) and re-importing it would be
    // wasted work with de-dup risk. A production build would instead
    // track a per-contact high-water mark; a fixed lookback keeps this
    // scaffold simple and still correct.
    final since = DateTime.now().subtract(const Duration(days: 14));

    for (final contact in contacts) {
      if (contact.phoneNumbers.isEmpty) continue;
      final events = await _channel.fetchEventsSince(
        phoneNumbers: contact.phoneNumbers,
        since: since,
      );
      for (final event in events) {
        final source =
            event.isCall ? InteractionSource.call : InteractionSource.text;
        final alreadyLogged = await _database.interactionExists(
          contactId: contact.id,
          timestamp: event.timestamp,
          source: source,
        );
        if (alreadyLogged) continue;

        await _database.logInteraction(
          Interaction()
            ..contactId = contact.id
            ..timestamp = event.timestamp
            ..source = source
            ..durationSeconds = event.durationSeconds,
        );
      }
    }
  }
}
