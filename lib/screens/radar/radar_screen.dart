import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../services/scoring_service.dart';
import '../checkin/checkin_modal.dart';
import '../settings/settings_screen.dart';
import 'contact_detail_sheet.dart';
import 'radar_data_provider.dart';
import 'radar_painter.dart';
import 'radar_point.dart';

const _ringCount = 4; // matches ScoringService's 2/3/3/2 template

/// The core screen from DESIGN.md §8. Recalculates hourly in the
/// background; pull-to-refresh forces an out-of-cycle recompute, useful
/// right after logging a check-in.
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  DateTime? _lastUpdated;

  Future<void> _refresh() async {
    final database = ref.read(appDatabaseProvider);
    await ScoringService(database).recomputeTick();
    setState(() => _lastUpdated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(radarPointsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your circle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CheckinModal.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Log a catch-up'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: pointsAsync.when(
          data: (points) => _RadarBody(
            points: points,
            lastUpdated: _lastUpdated,
            onTapPoint: (point) => ContactDetailSheet.show(context, point),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ),
    );
  }
}

class _RadarBody extends StatelessWidget {
  const _RadarBody({
    required this.points,
    required this.lastUpdated,
    required this.onTapPoint,
  });

  final List<RadarPoint> points;
  final DateTime? lastUpdated;
  final void Function(RadarPoint) onTapPoint;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Your radar fills in as you interact — check back in an '
              'hour, or log a catch-up now.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              width: constraints.maxWidth,
              height: side,
              child: GestureDetector(
                onTapUp: (details) => _handleTap(details, side, side),
                child: CustomPaint(
                  painter: RadarPainter(points: points, ringCount: _ringCount),
                  size: Size(side, side),
                ),
              ),
            ),
            if (lastUpdated != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Last updated ${_minutesAgo(lastUpdated!)}m ago',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleTap(TapUpDetails details, double width, double height) {
    // Hit-test against each point's known on-screen position, reusing the
    // painter's own placement math so taps and drawing never drift apart.
    final center = Offset(width / 2, height / 2);
    final maxRadius =
        math.min(width, height) / 2 - RadarPainter.avatarRadius - 8;

    for (final point in points) {
      final ringRadius = point.ring == 0
          ? maxRadius / _ringCount * 0.55
          : maxRadius * (point.ring + 1) / _ringCount;
      const goldenAngle = 2.399963;
      final angle = (point.contactId * goldenAngle) % (2 * math.pi);
      final offset = center +
          Offset(math.cos(angle), math.sin(angle)) * ringRadius;

      if ((details.localPosition - offset).distance <=
          RadarPainter.avatarRadius) {
        onTapPoint(point);
        return;
      }
    }
  }

  int _minutesAgo(DateTime time) =>
      DateTime.now().difference(time).inMinutes;
}
