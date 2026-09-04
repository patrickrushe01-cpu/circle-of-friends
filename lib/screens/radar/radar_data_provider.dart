import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import 'radar_point.dart';

/// Assembles the current [RadarPoint] set from the database's contacts +
/// last-two-ticks scores, per DESIGN.md §5. Rebuilds whenever `scores`
/// changes (an hourly tick, or a manual pull-to-refresh recompute).
final radarPointsProvider = StreamProvider<List<RadarPoint>>((ref) async* {
  final database = ref.watch(appDatabaseProvider);

  await for (final _ in database.watchScores()) {
    yield await _buildPoints(database);
  }
  // Emit once immediately even if no tick has ever run, so the screen can
  // show its empty state instead of hanging on loading forever.
});

Future<List<RadarPoint>> _buildPoints(AppDatabase database) async {
  final contacts = await database.trackedContacts();
  final ticksByContact = await database.lastTwoTicksByContact();

  final points = <RadarPoint>[];
  for (final contact in contacts) {
    final ticks = ticksByContact[contact.id];
    if (ticks == null || ticks.isEmpty) continue;

    final current = ticks.last;
    final previous = ticks.length > 1 ? ticks.first : null;

    final recent = await database.recentInteractionsForContact(
      contact.id,
      limit: 1,
    );

    points.add(
      RadarPoint(
        contactId: contact.id,
        name: contact.name,
        ring: current.ring,
        previousRing: previous?.ring,
        lastInteractionAt: recent.isNotEmpty ? recent.first.timestamp : null,
      ),
    );
  }
  return points;
}
