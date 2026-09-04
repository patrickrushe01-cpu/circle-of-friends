import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/permission_service.dart';

/// Step 2 of onboarding: request permissions one at a time with a
/// one-line reason each, rather than firing every OS dialog at once —
/// per DESIGN.md §8. Users can skip a permission and grant it later from
/// Settings; a skipped source simply contributes nothing to scoring
/// (handled by the re-normalization in [ScoringService]).
class PermissionStep extends StatefulWidget {
  const PermissionStep({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<PermissionStep> createState() => _PermissionStepState();
}

class _PermissionStepState extends State<PermissionStep> {
  final _service = const PermissionService();
  late final List<TrackedPermission> _order = _service.requestOrder;
  int _index = 0;
  PermissionStatus? _lastStatus;

  Future<void> _requestCurrent() async {
    final status = await _service.request(_order[_index]);
    setState(() => _lastStatus = status);
  }

  void _next() {
    if (_index == _order.length - 1) {
      widget.onComplete();
    } else {
      setState(() {
        _index++;
        _lastStatus = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = _order[_index];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${_index + 1} of ${_order.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 16),
          Text(
            _service.reasonFor(permission),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 32),
          if (_lastStatus == null)
            FilledButton(
              onPressed: _requestCurrent,
              child: const Text('Allow'),
            )
          else
            FilledButton(onPressed: _next, child: const Text('Continue')),
          TextButton(onPressed: _next, child: const Text('Skip for now')),
        ],
      ),
    );
  }
}
