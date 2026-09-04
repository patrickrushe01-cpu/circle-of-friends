import 'package:isar/isar.dart';

part 'score.g.dart';

/// Append-only: one row per contact per hourly recompute tick. Never
/// updated in place — this is what makes the ring-transition animation
/// possible (the UI diffs the last two ticks per contact).
@collection
class Score {
  Id id = Isar.autoIncrement;

  @Index()
  late int contactId;

  @Index()
  late DateTime computedAt;

  late double rawScore;

  /// 1 (closest) through the size of the tracked set.
  late int rank;

  /// 0 (innermost ring) through the outermost ring index.
  late int ring;
}
