import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../widgets/map_widget.dart';
import '../models/route_info.dart';

class MapScreen extends StatefulWidget {
  final LocationService locationService;
  final AzureMapsService azureMapsService;
  final RouteInfo? activeRoute;
  final Function(RouteInfo?)? onRouteChanged;

  const MapScreen({
    super.key,
    required this.locationService,
    required this.azureMapsService,
    this.activeRoute,
    this.onRouteChanged,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  AzureMapsController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AzureMapsWidget(
            locationService: widget.locationService,
            azureMapsService: widget.azureMapsService,
            activeRoute: widget.activeRoute,
            onRouteChanged: widget.onRouteChanged,
            onControllerReady: (controller) {
              setState(() {
                _mapController = controller;
              });
            },
          ),

          // Re-center FAB (shown when map controller is ready and auto-follow is off)
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'map_center_fab',
              onPressed: () {
                _mapController?.centerOnLocation();
              },
              child: const Icon(Icons.gps_fixed),
            ),
          ),

          // Hint text at bottom
          Positioned(
            bottom: 24,
            left: 16,
            right: 80,
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Tap on map to set destination',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
