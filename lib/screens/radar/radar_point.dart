/// A single contact's position on the radar for the current tick, plus
/// enough of its previous tick to drive the ring-transition animation
/// described in DESIGN.md §5/§8.
class RadarPoint {
  const RadarPoint({
    required this.contactId,
    required this.name,
    required this.ring,
    required this.previousRing,
    required this.lastInteractionAt,
  });

  final int contactId;
  final String name;
  final int ring;
  final int? previousRing;
  final DateTime? lastInteractionAt;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String get lastInteractionLabel {
    if (lastInteractionAt == null) return 'No interactions yet';
    final days = DateTime.now().difference(lastInteractionAt!).inDays;
    if (days == 0) return 'Last in touch today';
    if (days == 1) return 'Last in touch 1 day ago';
    return 'Last in touch $days days ago';
  }
}
