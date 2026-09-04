import 'dart:math' as math;

import '../database/app_database.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/score.dart';

/// The decay-weighted scoring engine described in DESIGN.md §6.
///
/// Runs identically on both platforms — the platform difference lives
/// entirely in which [InteractionSource]s have any rows to pull, not in
/// this math. An iOS install simply never has `call`/`text` rows, and the
/// weight re-normalization step keeps that install's scores from being
/// structurally deflated relative to an Android one.
class ScoringService {
  ScoringService(this._database);

  final AppDatabase _database;

  static const _lookback = Duration(days: 14);

  /// Base weights before per-install re-normalization. Tuned so a call and
  /// a calendar meeting count as full-strength "we spent time together"
  /// signals, texts and manual "other" check-ins count as lighter-weight
  /// confirmations, and email counts as the weakest signal (easy to send
  /// without real closeness).
  static const Map<InteractionSource, double> _baseSourceWeight = {
    InteractionSource.call: 1.0,
    InteractionSource.calendar: 1.0,
    InteractionSource.manual: 0.8,
    InteractionSource.text: 0.5,
    InteractionSource.email: 0.4,
  };

  /// Decay constant: an interaction 14 days old contributes ~10% of the
  /// weight a same-hour interaction does. Solved from
  /// exp(-lambda * 14*24) = 0.10.
  static final double _lambdaPerHour =
      -math.log(0.10) / (14 * 24);

  /// Runs one hourly tick: scores every active contact, ranks them, buckets
  /// them into rings, and persists the result. Call this from the
  /// background job (see [RecomputeScheduler]) and also on-demand after a
  /// manual check-in / pull-to-refresh.
  Future<void> recomputeTick({DateTime? now}) async {
    final tick = now ?? DateTime.now();
    final contacts = await _database.trackedContacts();
    if (contacts.isEmpty) return;

    final since = tick.subtract(_lookback);
    final rawScores = <Contact, double>{};

    for (final contact in contacts) {
      final interactions = await _database.interactionsSince(
        contact.id,
        since,
      );
      rawScores[contact] = _scoreContact(interactions, tick);
    }

    final ranked = contacts.toList()
      ..sort((a, b) => rawScores[b]!.compareTo(rawScores[a]!));

    final ringOf = _ringAssignments(ranked.length);

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

  double _scoreContact(List<Interaction> interactions, DateTime tick) {
    if (interactions.isEmpty) return 0;

    // Re-normalize source weights to whatever sources actually appear in
    // this contact's (and by extension, this install's) interaction
    // history, so a platform missing a signal isn't penalized structurally
    // — see DESIGN.md §2 and §6.
    final presentSources = interactions.map((i) => i.source).toSet();
    final totalBaseWeight = presentSources.fold<double>(
      0,
      (sum, source) => sum + _baseSourceWeight[source]!,
    );
    final normalizationFactor =
        totalBaseWeight == 0 ? 1.0 : presentSources.length / totalBaseWeight;

    var total = 0.0;
    for (final interaction in interactions) {
      final ageHours =
          tick.difference(interaction.timestamp).inMinutes / 60.0;
      if (ageHours < 0) continue; // ignore clock-skew edge cases
      final decay = math.exp(-_lambdaPerHour * ageHours);
      final weight =
          _baseSourceWeight[interaction.source]! * normalizationFactor;
      total += weight * decay;
    }
    return total;
  }

  /// Fixed-size ring buckets for the ten-contact default, per DESIGN.md
  /// §6's v1 choice (rings of 2/3/3/2, innermost first). Scales gracefully
  /// if the tracked set is ever a different size.
  List<int> _ringAssignments(int contactCount) {
    if (contactCount == 0) return const [];
    const template = [2, 3, 3, 2];
    final assignments = <int>[];
    var remaining = contactCount;
    for (var ring = 0; ring < template.length && remaining > 0; ring++) {
      final take = math.min(template[ring], remaining);
      assignments.addAll(List.filled(take, ring));
      remaining -= take;
    }
    // Any overflow beyond the template (tracked set > 10) goes to the
    // outermost ring rather than growing new rings.
    if (remaining > 0) {
      assignments.addAll(List.filled(remaining, template.length - 1));
    }
    return assignments;
  }
}
