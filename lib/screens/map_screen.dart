import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../services/navigation_guidance_service.dart';
import '../widgets/map_widget.dart';
import '../models/route_info.dart';

class MapScreen extends StatefulWidget {
  final LocationService locationService;
  final AzureMapsService azureMapsService;
  final NavigationGuidanceService navigationService;
  final RouteInfo? activeRoute;
  final Function(RouteInfo?)? onRouteChanged;

  const MapScreen({
    super.key,
    required this.locationService,
    required this.azureMapsService,
    required this.navigationService,
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
                  activeRoute: widget.activeRoute,
                  onRouteChanged: _handleRouteChanged,
                  onControllerReady: (controller) {
                    setState(() {
                      _mapController = controller;
                    });
                  },
                ),

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
