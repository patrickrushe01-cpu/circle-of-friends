import '../database/app_database.dart';
import '../models/contact.dart';
import '../models/score.dart';
import 'scoring_math.dart';

/// The decay-weighted scoring engine described in DESIGN.md §6. The math
/// itself lives in [ScoringMath] (pure, unit-testable); this class is the
/// I/O shell that pulls interactions, invokes it, and persists the result.
///
/// Runs identically on both platforms — the platform difference lives
/// entirely in which [InteractionSource]s have any rows to pull, not in
/// the math. An iOS install simply never has `call`/`text` rows, and the
/// weight re-normalization step keeps that install's scores from being
/// structurally deflated relative to an Android one.
class ScoringService {
  ScoringService(this._database);

  final AppDatabase _database;

  /// Runs one hourly tick: scores every active contact, ranks them, buckets
  /// them into rings, and persists the result. Call this from the
  /// background job (see [RecomputeScheduler]) and also on-demand after a
  /// manual check-in / pull-to-refresh.
  Future<void> recomputeTick({DateTime? now}) async {
    final tick = now ?? DateTime.now();
    final contacts = await _database.trackedContacts();
    if (contacts.isEmpty) return;

    final since = tick.subtract(ScoringMath.lookback);
    final rawScores = <Contact, double>{};

    for (final contact in contacts) {
      final interactions = await _database.interactionsSince(
        contact.id,
        since,
      );
      rawScores[contact] = ScoringMath.scoreContact(interactions, tick);
    }

    final ranked = contacts.toList()
      ..sort((a, b) => rawScores[b]!.compareTo(rawScores[a]!));

    final ringOf = ScoringMath.ringAssignments(ranked.length);

    final scores = <Score>[
      for (var i = 0; i < ranked.length; i++)
        Score()
          ..contactId = ranked[i].id
          ..computedAt = tick
          ..rawScore = rawScores[ranked[i]]!
          ..rank = i + 1
          ..ring = ringOf[i],
    ];

    await _database.writeScoresForTick(scores);
  }
}
