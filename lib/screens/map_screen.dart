import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../services/navigation_guidance_service.dart';
import '../services/heading_service.dart';
import '../widgets/map_widget.dart';
import '../models/route_info.dart';

class MapScreen extends StatefulWidget {
  final LocationService locationService;
  final AzureMapsService azureMapsService;
  final NavigationGuidanceService navigationService;
  final HeadingService headingService;
  final RouteInfo? activeRoute;
  final Function(RouteInfo?)? onRouteChanged;

  const MapScreen({
    super.key,
    required this.locationService,
    required this.azureMapsService,
    required this.navigationService,
    required this.headingService,
    this.activeRoute,
    this.onRouteChanged,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  AzureMapsController? _mapController;
  GuidanceState? _guidanceState;

  @override
  void initState() {
    super.initState();
    widget.navigationService.onGuidanceStateChanged = (state) {
      setState(() {
        _guidanceState = state;
      });
    };
  }

  @override
  void dispose() {
    widget.navigationService.onGuidanceStateChanged = null;
    super.dispose();
  }

  void _handleRouteChanged(RouteInfo? route) {
    if (route != null) {
      widget.navigationService.startGuidance(route);
    } else {
      widget.navigationService.stopGuidance();
      setState(() {
        _guidanceState = null;
      });
    }
    widget.onRouteChanged?.call(route);
  }

  /// Build prominent turn guidance overlay
  Widget _buildTurnGuidanceOverlay() {
    final delta = _guidanceState!.headingDelta!;
    final absDelta = delta.abs();

    // Don't show if roughly on course
    if (absDelta < 15) {
      return const SizedBox.shrink();
    }

    // Determine turn direction and intensity
    final isRight = delta > 0;
    final icon = isRight ? Icons.turn_right : Icons.turn_left;

    String instruction;
    Color backgroundColor;
    double iconSize;

    if (absDelta > 150) {
      instruction = 'TURN AROUND';
      backgroundColor = Colors.red;
      iconSize = 80;
    } else if (absDelta > 60) {
      instruction = isRight ? 'TURN RIGHT' : 'TURN LEFT';
      backgroundColor = Colors.orange;
      iconSize = 70;
    } else if (absDelta > 30) {
      instruction = isRight ? 'SLIGHT RIGHT' : 'SLIGHT LEFT';
      backgroundColor = Colors.amber;
      iconSize = 60;
    } else {
      instruction = isRight ? 'Adjust right' : 'Adjust left';
      backgroundColor = Colors.yellow.shade700;
      iconSize = 50;
    }

    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: iconSize,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${absDelta.round()}° off course',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveRoute = widget.activeRoute != null;

    return Scaffold(
      body: Column(
        children: [
          // Main map area (expanded)
          Expanded(
            child: Stack(
              children: [
                AzureMapsWidget(
                  locationService: widget.locationService,
                  azureMapsService: widget.azureMapsService,
                  headingService: widget.headingService,
                  activeRoute: widget.activeRoute,
                  onRouteChanged: _handleRouteChanged,
                  onControllerReady: (controller) {
                    setState(() {
                      _mapController = controller;
                    });
                  },
                ),

                // PROMINENT TURN GUIDANCE OVERLAY
                if (_guidanceState != null && _guidanceState!.headingDelta != null)
                  _buildTurnGuidanceOverlay(),

                // Re-center FAB
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
                    heroTag: 'map_center_fab',
                    mini: true,
                    onPressed: () {
                      _mapController?.centerOnLocation();
                    },
                    child: const Icon(Icons.gps_fixed),
                  ),
                ),

                // Hint text (only when no route)
                if (!hasActiveRoute)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 80,
                    child: Card(
                      color: Colors.black54,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'Tap on map to set destination',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom guidance bar (only when route is active)
          if (hasActiveRoute)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // Left: Distance and time remaining
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _guidanceState?.formattedRemainingDistance ??
                                widget.activeRoute!.formattedDistance,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _guidanceState?.formattedRemainingTime ??
                                widget.activeRoute!.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right: Next instruction
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _guidanceState?.nextCheckpoint?.instruction ??
                                'Follow route',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_guidanceState != null)
                            Text(
                              '${_guidanceState!.completedCheckpoints}/${_guidanceState!.totalCheckpoints} steps',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
