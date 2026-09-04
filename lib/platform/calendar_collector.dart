import 'package:device_calendar/device_calendar.dart';

import '../database/app_database.dart';
import '../models/contact.dart';
import '../models/interaction.dart';

/// Pulls calendar meetings that include a tracked contact into the shared
/// `interactions` table. Cross-platform per DESIGN.md §2 — this is one of
/// the two baseline signals iOS relies on in place of call/SMS access,
/// backed by EventKit there and CalendarContract on Android via the
/// `device_calendar` plugin either way.
class CalendarCollector {
  CalendarCollector(this._database, {DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  final AppDatabase _database;
  final DeviceCalendarPlugin _plugin;

  static const _lookback = Duration(days: 14);

  /// Fetches events across every calendar on the device in the trailing
  /// window and logs one `Interaction` per (contact, event) match on
  /// attendee email. A meeting with two tracked contacts logs against both.
  Future<void> syncSinceLastRun() async {
    final permissionsGranted = await _plugin.hasPermissions();
    if (permissionsGranted.data != true) return;

    final contacts = await _database.trackedContacts();
    final contactsByEmail = <String, Contact>{
      for (final contact in contacts)
        for (final email in contact.emailAddresses)
          email.toLowerCase(): contact,
    };
    if (contactsByEmail.isEmpty) return;

    final calendarsResult = await _plugin.retrieveCalendars();
    final calendars = calendarsResult.data ?? [];
    if (calendars.isEmpty) return;

    final now = DateTime.now();
    final since = now.subtract(_lookback);

    for (final calendar in calendars) {
      if (calendar.id == null) continue;
      final eventsResult = await _plugin.retrieveEvents(
        calendar.id,
        RetrieveEventsParams(startDate: since, endDate: now),
      );
      final events = eventsResult.data ?? [];

      for (final event in events) {
        final start = event.start;
        if (start == null) continue;

        final matchedContacts = <Contact>{};
        for (final attendee in event.attendees ?? const []) {
          final email = attendee?.emailAddress?.toLowerCase();
          if (email == null) continue;
          final contact = contactsByEmail[email];
          if (contact != null) matchedContacts.add(contact);
        }
        if (matchedContacts.isEmpty) continue;

        final duration = event.end != null
            ? event.end!.difference(start).inSeconds
            : null;

        for (final contact in matchedContacts) {
          final alreadyLogged = await _database.interactionExists(
            contactId: contact.id,
            timestamp: start,
            source: InteractionSource.calendar,
          );
          if (alreadyLogged) continue;

          await _database.logInteraction(
            Interaction()
              ..contactId = contact.id
              ..timestamp = start
              ..source = InteractionSource.calendar
              ..durationSeconds = duration,
          );
        }
      }
    }
  }
}
