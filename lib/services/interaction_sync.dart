import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../platform/android_interaction_collector.dart';
import '../platform/calendar_collector.dart';
import '../platform/email/email_collector.dart';

/// Runs every interaction collector for whatever sources are actually
/// available on this install (see DESIGN.md §2), then leaves scoring to
/// the caller. Shared by the background hourly tick and the radar
/// screen's pull-to-refresh so the two paths can't drift apart.
///
/// Each collector is isolated with its own try/catch: a denied permission
/// or a network hiccup on one signal (e.g. email) must never block the
/// others from running or crash the recompute tick — a missing signal
/// degrades that contact's score, it doesn't break the app.
class InteractionSync {
  InteractionSync(this._database);

  final AppDatabase _database;

  Future<void> syncAll() async {
    await _guarded(
      'android call/sms',
      () => AndroidInteractionCollector(_database).syncSinceLastRun(),
    );
    await _guarded(
      'calendar',
      () => CalendarCollector(_database).syncSinceLastRun(),
    );
    await _guarded(
      'email',
      () => EmailCollector(_database).syncSinceLastRun(),
    );
  }

  Future<void> _guarded(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      // A collector failing (denied permission, no network, expired OAuth
      // token) should never take the whole recompute tick down with it.
      debugPrint('InteractionSync: $label collector failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
