import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/event_models.dart';
import '../recorder/recorder_controller.dart';
import '../synthesis/test_synthesizer.dart';

/// A floating diagnostic widget providing one-tap access to flight logs,
/// session export, and instant `testWidgets` code generation in staging/dogfood builds.
class FlightRecorderOverlay extends StatefulWidget {
  final Widget child;
  final bool enableInRelease;

  const FlightRecorderOverlay({
    super.key,
    required this.child,
    this.enableInRelease = false,
  });

  /// Tracks whether [globalPosition] hits the floating recorder button or open modal.
  /// Used by [PointerInterceptor] to avoid recording taps on the diagnostic UI itself.
  static bool isOverlayPoint(Offset globalPosition) {
    if (_isModalOpen) return true;
    for (final rect in _activeButtonRects) {
      if (rect.inflate(16.0).contains(globalPosition)) return true;
    }
    return false;
  }

  static bool _isModalOpen = false;
  static final Set<Rect> _activeButtonRects = {};

  @override
  State<FlightRecorderOverlay> createState() => _FlightRecorderOverlayState();
}

class _FlightRecorderOverlayState extends State<FlightRecorderOverlay> {
  Offset _buttonPosition = const Offset(20, 100);

  @override
  void initState() {
    super.initState();
    _updateButtonRect();
  }

  void _updateButtonRect() {
    FlightRecorderOverlay._activeButtonRects
      ..clear()
      ..add(Rect.fromLTWH(_buttonPosition.dx, _buttonPosition.dy, 48, 48));
  }

  @override
  void dispose() {
    FlightRecorderOverlay._activeButtonRects.clear();
    FlightRecorderOverlay._isModalOpen = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directionality = Directionality.maybeOf(context) ?? TextDirection.ltr;

    return Directionality(
      textDirection: directionality,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          widget.child,
          Positioned(
            left: _buttonPosition.dx,
            top: _buttonPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                final screenSize =
                    MediaQuery.maybeSizeOf(context) ?? const Size(800, 1200);
                final newX = (_buttonPosition.dx + details.delta.dx).clamp(
                    0.0, (screenSize.width - 56.0).clamp(0.0, double.infinity));
                final newY = (_buttonPosition.dy + details.delta.dy).clamp(0.0,
                    (screenSize.height - 56.0).clamp(0.0, double.infinity));
                setState(() {
                  _buttonPosition = Offset(newX, newY);
                  _updateButtonRect();
                });
              },
              child: Material(
                color: Colors.black87,
                shape: const CircleBorder(
                  side: BorderSide(color: Colors.redAccent, width: 1.5),
                ),
                elevation: 6,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showSessionModal(context),
                  child: const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Icon(
                      Icons.fiber_smart_record,
                      size: 22,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSessionModal(BuildContext context) async {
    final recentEvents = FlightRecorder.instance.getRecentEvents();
    final modalContext =
        FlightRecorder.instance.navigatorObserver.navigator?.context ?? context;
    FlightRecorderOverlay._isModalOpen = true;
    try {
      await showModalBottomSheet(
        context: modalContext,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          String selectedFilter = 'All';
          final events = List<FlightEvent>.from(recentEvents);

          return StatefulBuilder(
            builder: (context, setModalState) {
              final filtered = events.where((e) {
                return switch (selectedFilter) {
                  'Errors' => e is CrashFlightEvent,
                  'Network' =>
                    e is HttpFlightEvent || e is WebSocketFlightEvent,
                  'Taps' =>
                    e is PointerFlightEvent || e is SemanticPointerFlightEvent,
                  'Nav' => e is NavigationFlightEvent,
                  _ => true,
                };
              }).toList();

              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                maxChildSize: 0.95,
                minChildSize: 0.4,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.flight_takeoff,
                                    color: Colors.cyanAccent),
                                SizedBox(width: 8),
                                Text(
                                  'Flight Recorder',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '${filtered.length}/${events.length}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_sweep,
                                      color: Colors.redAccent, size: 20),
                                  tooltip: 'Clear Buffer',
                                  onPressed: () {
                                    FlightRecorder.instance.clear();
                                    setModalState(() {
                                      events.clear();
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Buffer cleared!')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              'All',
                              'Errors',
                              'Network',
                              'Taps',
                              'Nav'
                            ].map((tag) {
                              final isSel = selectedFilter == tag;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: ChoiceChip(
                                  label: Text(tag),
                                  selected: isSel,
                                  selectedColor: Colors.cyanAccent,
                                  labelStyle: TextStyle(
                                    color:
                                        isSel ? Colors.black : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (_) {
                                    setModalState(() {
                                      selectedFilter = tag;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyan,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () async {
                                  final session =
                                      FlightRecorder.instance.snapshot();
                                  final testCode = FlightSynthesizer.synthesize(
                                    session: session,
                                  );
                                  await Clipboard.setData(
                                      ClipboardData(text: testCode));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Synthesized testWidgets code copied to clipboard!'),
                                      ),
                                    );
                                    Navigator.pop(context);
                                  }
                                },
                                icon: const Icon(Icons.code),
                                label: const Text('Copy Dart Test'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amberAccent,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () async {
                                  final file = await FlightRecorder.instance
                                      .exportSession();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text('Saved to ${file.path}')),
                                    );
                                    Navigator.pop(context);
                                  }
                                },
                                icon: const Icon(Icons.file_download),
                                label: const Text('Export .flightlog'),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white24, height: 24),
                        Text(
                          'Recent Timeline (${filtered.length} visible):',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text('No events matching filter',
                                      style: TextStyle(color: Colors.white38)),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final event = filtered[index];
                                    return _buildEventTile(event);
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      FlightRecorderOverlay._isModalOpen = false;
    }
  }

  Widget _buildEventTile(FlightEvent event) {
    final (icon, title, subtitle, color) = switch (event) {
      SemanticPointerFlightEvent sp => (
          Icons.touch_app,
          'Semantic ${sp.action.toUpperCase()} [${sp.resolvedKey ?? sp.resolvedText ?? sp.resolvedType ?? '(${sp.dx.toInt()}, ${sp.dy.toInt()})'}]',
          '${sp.deviceKind} • +${sp.timestampMs}ms',
          Colors.amber,
        ),
      PointerFlightEvent p => (
          Icons.touch_app,
          'Pointer ${p.action.toUpperCase()} (${p.dx.toInt()}, ${p.dy.toInt()})',
          '${p.deviceKind} - +${p.timestampMs}ms',
          Colors.orangeAccent,
        ),
      NavigationFlightEvent n => (
          Icons.navigation,
          'Route ${n.action.toUpperCase()} -> ${n.routeName}',
          '+${n.timestampMs}ms',
          Colors.lightBlueAccent,
        ),
      HttpFlightEvent h => (
          Icons.http,
          '${h.method} ${h.url}',
          'Status: ${h.statusCode} • ${h.durationMs}ms',
          h.statusCode >= 400 ? Colors.redAccent : Colors.greenAccent,
        ),
      LifecycleFlightEvent l => (
          Icons.sync,
          'Lifecycle: ${l.state}',
          '+${l.timestampMs}ms',
          Colors.purpleAccent,
        ),
      CrashFlightEvent c => (
          Icons.error_outline,
          'CRASH: ${c.exception}',
          '+${c.timestampMs}ms',
          Colors.red,
        ),
      CustomBreadcrumbFlightEvent b => (
          Icons.bookmark_border,
          'Breadcrumb: ${b.name}',
          'Category: ${b.category}',
          Colors.tealAccent,
        ),
      TextInputFlightEvent t => (
          Icons.keyboard,
          'Input: ${t.action} [${t.fieldKey ?? t.fieldType ?? 'Field'}]',
          '"${t.redactedText ?? ''}" • +${t.timestampMs}ms',
          Colors.lightGreenAccent,
        ),
      PlatformChannelFlightEvent pc => (
          Icons.settings_cell,
          'Channel: ${pc.channelName}',
          '${pc.direction}: ${pc.methodName ?? 'event'} • +${pc.timestampMs}ms',
          Colors.blueGrey,
        ),
      WebSocketFlightEvent ws => (
          Icons.swap_horiz,
          'WS: ${ws.direction} (${ws.url})',
          '${ws.message ?? ''} • +${ws.timestampMs}ms',
          Colors.cyan,
        ),
      RouteStackSnapshotEvent rs => (
          Icons.layers,
          'Route Stack Snapshot',
          '${rs.routeStack.join(' -> ')} • +${rs.timestampMs}ms',
          Colors.indigoAccent,
        ),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
