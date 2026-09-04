import 'package:flutter_test/flutter_test.dart';

import 'package:circle_of_friends/models/interaction.dart';
import 'package:circle_of_friends/services/scoring_math.dart';

Interaction _interaction({
  required InteractionSource source,
  required DateTime timestamp,
}) {
  return Interaction()
    ..contactId = 1
    ..timestamp = timestamp
    ..source = source;
}

void main() {
  group('ScoringMath.scoreContact', () {
    final tick = DateTime(2026, 1, 15, 12);

    test('empty history scores zero', () {
      expect(ScoringMath.scoreContact([], tick), 0);
    });

    test('a same-hour interaction scores its full base weight', () {
      final score = ScoringMath.scoreContact(
        [_interaction(source: InteractionSource.call, timestamp: tick)],
        tick,
      );
      // Single source present -> normalization factor is 1 / baseWeight,
      // so the result is exactly baseWeight * factor * decay(0) == 1.0.
      expect(score, closeTo(1.0, 1e-9));
    });

    test('recent interactions outweigh a pile of old ones', () {
      final recentCall = ScoringMath.scoreContact(
        [
          _interaction(
            source: InteractionSource.call,
            timestamp: tick.subtract(const Duration(hours: 1)),
          ),
        ],
        tick,
      );

      final manyOldCalls = ScoringMath.scoreContact(
        List.generate(
          3,
          (_) => _interaction(
            source: InteractionSource.call,
            timestamp: tick.subtract(const Duration(days: 13, hours: 23)),
          ),
        ),
        tick,
      );

      // Three 14-day-old calls (~10% weight each, ~0.3 total) still lose to
      // one call an hour ago (~full weight) — recency dominates by design.
      expect(recentCall, greaterThan(manyOldCalls));
    });

    test('a 14-day-old interaction retains roughly 10% of its weight', () {
      final freshScore = ScoringMath.scoreContact(
        [_interaction(source: InteractionSource.call, timestamp: tick)],
        tick,
      );
      final oldScore = ScoringMath.scoreContact(
        [
          _interaction(
            source: InteractionSource.call,
            timestamp: tick.subtract(const Duration(days: 14)),
          ),
        ],
        tick,
      );
      expect(oldScore / freshScore, closeTo(0.10, 0.01));
    });

    test('future timestamps (clock skew) are ignored, not negative-aged', () {
      final score = ScoringMath.scoreContact(
        [
          _interaction(
            source: InteractionSource.call,
            timestamp: tick.add(const Duration(hours: 1)),
          ),
        ],
        tick,
      );
      expect(score, 0);
    });

    test('missing a signal on iOS does not structurally deflate the score',
        () {
      // Same single-event shape, different sources — re-normalization
      // should put both installs on equal footing rather than penalizing
      // whichever platform's install only ever sees a text.
      final iosOnlyText = ScoringMath.scoreContact(
        [_interaction(source: InteractionSource.text, timestamp: tick)],
        tick,
      );
      final androidOnlyCall = ScoringMath.scoreContact(
        [_interaction(source: InteractionSource.call, timestamp: tick)],
        tick,
      );
      expect(iosOnlyText, closeTo(androidOnlyCall, 1e-9));
    });
  });

  group('ScoringMath.ringAssignments', () {
    test('empty set has no rings', () {
      expect(ScoringMath.ringAssignments(0), isEmpty);
    });

    test('ten contacts follow the 2/3/3/2 template innermost-first', () {
      expect(
        ScoringMath.ringAssignments(10),
        [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
      );
    });

    test('fewer than ten contacts fill rings in order without gaps', () {
      expect(ScoringMath.ringAssignments(4), [0, 0, 1, 1]);
    });

    test('more than ten overflows into the outermost ring', () {
      final rings = ScoringMath.ringAssignments(12);
      expect(rings.length, 12);
      expect(rings.sublist(10), [3, 3]);
    });
  });
}
