import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'radar_point.dart';

/// Draws the concentric-ring radar and positions each contact's avatar on
/// its ring, per DESIGN.md §8. Each point's angle is deterministic
/// (hashed from its contact id) so a contact doesn't jitter position
/// between ticks unless its ring actually changes.
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.points,
    required this.ringCount,
    this.avatarImages = const {},
  });

  final List<RadarPoint> points;
  final int ringCount;
  final Map<int, ui.Image> avatarImages;

  static const double avatarRadius = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = math.min(size.width, size.height) / 2 - avatarRadius - 8;

    _drawRingGuides(canvas, center, maxRadius);
    _drawCenterMarker(canvas, center);

    for (final point in points) {
      _drawAvatar(canvas, center, maxRadius, point);
    }
  }

  void _drawRingGuides(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var ring = 1; ring <= ringCount; ring++) {
      final radius = maxRadius * ring / ringCount;
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawCenterMarker(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
  }

  void _drawAvatar(
    Canvas canvas,
    Offset center,
    double maxRadius,
    RadarPoint point,
  ) {
    // Ring 0 (innermost) sits at a fraction of the first ring's radius so
    // it doesn't collide with the center marker; outer rings sit exactly
    // on their guide circle.
    final ringRadius = point.ring == 0
        ? maxRadius / ringCount * 0.55
        : maxRadius * (point.ring + 1) / ringCount;

    final angle = _deterministicAngle(point.contactId);
    final offset = center +
        Offset(math.cos(angle), math.sin(angle)) * ringRadius;

    final image = avatarImages[point.contactId];
    if (image != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromCircle(center: offset, radius: avatarRadius);
      canvas.save();
      final clipPath = Path()..addOval(dst);
      canvas.clipPath(clipPath);
      canvas.drawImageRect(image, src, dst, Paint());
      canvas.restore();
    } else {
      canvas.drawCircle(
        offset,
        avatarRadius,
        Paint()..color = Colors.primaries[point.contactId % Colors.primaries.length],
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: point.initials,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  /// A stable angle per contact, spread across the circle by a golden-
  /// angle hash so ten contacts rarely land close together regardless of
  /// id ordering.
  double _deterministicAngle(int contactId) {
    const goldenAngle = 2.399963; // radians
    return (contactId * goldenAngle) % (2 * math.pi);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return points != oldDelegate.points || ringCount != oldDelegate.ringCount;
  }
}
