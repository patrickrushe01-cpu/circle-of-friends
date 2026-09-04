import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/score.dart';

/// Overridden in main() once the real Isar instance is opened, so the
/// rest of the app only ever depends on this provider, never on Isar
/// directly.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

/// Thin wrapper around the Isar instance. Everything is on-device — there
/// is no server sync, per the brief.
class AppDatabase {
  AppDatabase._(this.isar);

  final Isar isar;

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [ContactSchema, InteractionSchema, ScoreSchema],
      directory: dir.path,
      name: 'circle_of_friends',
    );
    return AppDatabase._(isar);
  }

  // --- Contacts ---------------------------------------------------------

  Future<List<Contact>> trackedContacts() {
    return isar.contacts.filter().activeEqualTo(true).findAll();
  }

  Stream<List<Contact>> watchTrackedContacts() {
    return isar.contacts
        .filter()
        .activeEqualTo(true)
        .watch(fireImmediately: true);
  }

  Future<int> addContact(Contact contact) {
    return isar.writeTxn(() => isar.contacts.put(contact));
  }

  /// Swaps a tracked contact out (soft-delete) and a new one in, per
  /// DESIGN.md §7. Historical interactions/scores for [oldContactId] are
  /// retained, not deleted.
  Future<void> swapContact({
    required int oldContactId,
    required Contact newContact,
  }) {
    return isar.writeTxn(() async {
      final old = await isar.contacts.get(oldContactId);
      if (old != null) {
        old.active = false;
        await isar.contacts.put(old);
      }
      await isar.contacts.put(newContact);
    });
  }

  // --- Interactions -------------------------------------------------------

  Future<int> logInteraction(Interaction interaction) {
    return isar.writeTxn(() => isar.interactions.put(interaction));
  }

  /// Used by [AndroidInteractionCollector] to avoid re-importing the same
  /// call/SMS event on every sync pass, since it re-queries a fixed
  /// lookback window rather than tracking a per-contact high-water mark.
  Future<bool> interactionExists({
    required int contactId,
    required DateTime timestamp,
    required InteractionSource source,
  }) {
    return isar.interactions
        .filter()
        .contactIdEqualTo(contactId)
        .and()
        .timestampEqualTo(timestamp)
        .and()
        .sourceEqualTo(source)
        .isEmpty()
        .then((empty) => !empty);
  }

  Future<List<Interaction>> interactionsSince(
    int contactId,
    DateTime since,
  ) {
    return isar.interactions
        .filter()
        .contactIdEqualTo(contactId)
        .and()
        .timestampGreaterThan(since)
        .sortByTimestampDesc()
        .findAll();
  }

  Future<List<Interaction>> recentInteractionsForContact(
    int contactId, {
    int limit = 20,
  }) {
    return isar.interactions
        .filter()
        .contactIdEqualTo(contactId)
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
  }

  // --- Scores -------------------------------------------------------------

  Future<void> writeScoresForTick(List<Score> scores) {
    return isar.writeTxn(() => isar.scores.putAll(scores));
  }

  /// The two most recent ticks per contact, oldest first — exactly what the
  /// radar needs to tween a ring transition.
  Future<Map<int, List<Score>>> lastTwoTicksByContact() async {
    final latestTick = await isar.scores
        .where()
        .sortByComputedAtDesc()
        .findFirst();
    if (latestTick == null) return {};

    final allTicks = await isar.scores
        .filter()
        .computedAtLessThan(
          latestTick.computedAt.add(const Duration(seconds: 1)),
        )
        .sortByComputedAtDesc()
        .findAll();

    final byContact = <int, List<Score>>{};
    for (final score in allTicks) {
      final list = byContact.putIfAbsent(score.contactId, () => []);
      if (list.length < 2) list.add(score);
    }
    for (final list in byContact.values) {
      list.sort((a, b) => a.computedAt.compareTo(b.computedAt));
    }
    return byContact;
  }

  Stream<void> watchScores() {
    return isar.scores.watchLazy(fireImmediately: true);
  }
}
