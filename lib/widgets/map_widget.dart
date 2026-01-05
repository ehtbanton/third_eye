import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../models/route_info.dart';

class AzureMapsWidget extends StatefulWidget {
  final LocationService locationService;
  final AzureMapsService azureMapsService;
  final RouteInfo? activeRoute;
  final Function(RouteInfo?)? onRouteChanged;
  final Function(AzureMapsController)? onControllerReady;

  const AzureMapsWidget({
    super.key,
    required this.locationService,
    required this.azureMapsService,
    this.activeRoute,
    this.onRouteChanged,
    this.onControllerReady,
  });

  @override
  State<AzureMapsWidget> createState() => _AzureMapsWidgetState();
}

class _AzureMapsWidgetState extends State<AzureMapsWidget> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _currentLocation;
  bool _autoFollow = true;
  bool _isLoading = false;
  RouteInfo? _currentRoute;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.activeRoute;
    _initLocation();
  }

  @override
  void didUpdateWidget(AzureMapsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeRoute != oldWidget.activeRoute) {
      setState(() {
        _currentRoute = widget.activeRoute;
      });
    }
  }

  Future<void> _initLocation() async {
    if (!widget.locationService.isInitialized) {
      final initialized = await widget.locationService.initialize();
      if (!initialized) {
        setState(() {
          _errorMessage = 'Could not access location';
        });
        return;
      }
    }

    // Get initial position
    final position = widget.locationService.currentPosition;
    if (position != null) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    }

    // Listen to position updates
    _locationSubscription = widget.locationService.locationStream.listen((position) {
      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = newLocation;
      });

      if (_autoFollow && mounted) {
        _mapController.move(newLocation, _mapController.camera.zoom);
      }
    });

    // Notify controller ready
    widget.onControllerReady?.call(AzureMapsController(
      centerOnLocation: _centerOnLocation,
      setAutoFollow: _setAutoFollow,
      clearRoute: _clearRoute,
    ));
  }

  void _centerOnLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
      setState(() {
        _autoFollow = true;
      });
    }
  }

  void _setAutoFollow(bool value) {
    setState(() {
      _autoFollow = value;
    });
  }

  void _clearRoute() {
    setState(() {
      _currentRoute = null;
    });
    widget.onRouteChanged?.call(null);
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS location...')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final route = await widget.azureMapsService.getRoute(_currentLocation!, point);

    setState(() {
      _isLoading = false;
      if (route != null) {
        _currentRoute = route;
        widget.onRouteChanged?.call(route);
      } else {
        _errorMessage = 'Could not calculate route';
      }
    });
  }

  void _onPositionChanged(MapCamera position, bool hasGesture) {
    if (hasGesture) {
      // User is panning manually
      setState(() {
        _autoFollow = false;
      });
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null && _currentLocation == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initLocation,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final initialCenter = _currentLocation ?? const LatLng(0, 0);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 16.0,
            onTap: _onMapTap,
            onPositionChanged: _onPositionChanged,
          ),
          children: [
            // Azure Maps tile layer
            TileLayer(
              urlTemplate: widget.azureMapsService.getTileUrl(),
              userAgentPackageName: 'com.example.third_eye',
            ),

            // Route polyline
            if (_currentRoute != null && _currentRoute!.routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _currentRoute!.routePoints,
                    color: Colors.blue,
                    strokeWidth: 5.0,
                  ),
                ],
              ),

            // Current location marker
            if (_currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  // Destination marker
                  if (_currentRoute != null)
                    Marker(
                      point: _currentRoute!.destination,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                ],
              ),
          ],
        ),

        // Loading indicator
        if (_isLoading)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ),

        // Waiting for GPS indicator
        if (_currentLocation == null)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Waiting for GPS...'),
                  ],
                ),
              ),
            ),
          ),

        // Error message
        if (_errorMessage != null && _currentLocation != null)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.red.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        // Route info card
        if (_currentRoute != null)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(Icons.directions, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentRoute!.summary,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Auto-follow indicator
        if (!_autoFollow)
          Positioned(
            bottom: 16,
            left: 16,
            child: FloatingActionButton.small(
              onPressed: _centerOnLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

class AzureMapsController {
  final VoidCallback centerOnLocation;
  final Function(bool) setAutoFollow;
  final VoidCallback clearRoute;

  AzureMapsController({
    required this.centerOnLocation,
    required this.setAutoFollow,
    required this.clearRoute,
  });
}
