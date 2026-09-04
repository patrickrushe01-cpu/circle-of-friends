import '../../database/app_database.dart';
import '../../models/interaction.dart';
import 'email_provider.dart';
import 'gmail_email_provider.dart';

/// Bridges [EmailProvider] frequency events into the shared
/// `interactions` table — the email half of the cross-platform baseline
/// described in DESIGN.md §2/§6. No-ops silently if no provider is
/// connected, exactly like the Android call/SMS collector no-ops on iOS:
/// email is an optional signal, not a required one.
class EmailCollector {
  EmailCollector(this._database, {EmailProvider? provider})
      : _provider = provider ?? GmailEmailProvider();

  final AppDatabase _database;
  final EmailProvider _provider;

  static const _lookback = Duration(days: 14);

  Future<void> syncSinceLastRun() async {
    if (!await _provider.isConnected()) return;

    final contacts = await _database.trackedContacts();
    if (contacts.isEmpty) return;

    final since = DateTime.now().subtract(_lookback);

    for (final contact in contacts) {
      if (contact.emailAddresses.isEmpty) continue;

      final events = await _provider.fetchEventsSince(
        contact.emailAddresses,
        since,
      );

      for (final event in events) {
        final alreadyLogged = await _database.interactionExists(
          contactId: contact.id,
          timestamp: event.timestamp,
          source: InteractionSource.email,
        );
        if (alreadyLogged) continue;

        await _database.logInteraction(
          Interaction()
            ..contactId = contact.id
            ..timestamp = event.timestamp
            ..source = InteractionSource.email,
        );
      }
    }
  }
}
