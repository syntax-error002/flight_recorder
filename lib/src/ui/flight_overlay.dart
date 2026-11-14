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

  @override
  State<FlightRecorderOverlay> createState() => _FlightRecorderOverlayState();
}

class _FlightRecorderOverlayState extends State<FlightRecorderOverlay> {
  Offset _buttonPosition = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _buttonPosition.dx,
          top: _buttonPosition.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _buttonPosition += details.delta;
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
    );
  }

  void _showSessionModal(BuildContext context) {
    final recentEvents = FlightRecorder.instance.getRecentEvents();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
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
                          Icon(Icons.flight_takeoff, color: Colors.cyanAccent),
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
                      Text(
                        '${recentEvents.length} events buffered',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyan,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () async {
                            final session = FlightRecorder.instance.snapshot();
                            final testCode = FlightSynthesizer.synthesize(
                              session: session,
                            );
                            await Clipboard.setData(ClipboardData(text: testCode));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Synthesized testWidgets code copied to clipboard!'),
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
                            final file = await FlightRecorder.instance.exportSession();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Saved to ${file.path}')),
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
                  const Text(
                    'Recent Timeline (Newest at Bottom):',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: recentEvents.length,
                      itemBuilder: (context, index) {
                        final event = recentEvents[index];
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
