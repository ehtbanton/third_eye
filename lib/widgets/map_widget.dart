import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../services/heading_service.dart';
import '../models/route_info.dart';

class AzureMapsWidget extends StatefulWidget {
  final LocationService locationService;
  final AzureMapsService azureMapsService;
  final HeadingService? headingService;
  final RouteInfo? activeRoute;
  final Function(RouteInfo?)? onRouteChanged;
  final Function(AzureMapsController)? onControllerReady;

  const AzureMapsWidget({
    super.key,
    required this.locationService,
    required this.azureMapsService,
    this.headingService,
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
  StreamSubscription<HeadingData>? _headingSubscription;
  LatLng? _currentLocation;
  double? _currentHeading; // Compass heading in degrees (0-360)
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

    // Listen to heading updates
    if (widget.headingService != null) {
      _headingSubscription = widget.headingService!.headingStream.listen((headingData) {
        setState(() {
          _currentHeading = headingData.heading;
        });
      });
    }

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
    _headingSubscription?.cancel();
    super.dispose();
  }

  /// Build location marker with heading direction indicator
  Widget _buildLocationMarkerWithHeading() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Heading cone/direction indicator
        if (_currentHeading != null)
          Transform.rotate(
            angle: (_currentHeading! * math.pi / 180), // Convert degrees to radians
            child: CustomPaint(
              size: const Size(60, 60),
              painter: _HeadingConePainter(),
            ),
          ),
        // Center dot (current location)
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        // Pulsing accuracy circle
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
          ),
        ),
      ],
    );
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

            // Checkpoint activation radius circles (20m)
            if (_currentRoute != null && _currentRoute!.checkpoints.isNotEmpty)
              CircleLayer(
                circles: _currentRoute!.checkpoints
                    .where((checkpoint) =>
                        checkpoint.location.latitude != 0 ||
                        checkpoint.location.longitude != 0)
                    .map((checkpoint) => CircleMarker(
                          point: checkpoint.location,
                          radius: 20, // 20 meters
                          useRadiusInMeter: true,
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderColor: Colors.orange.withValues(alpha: 0.5),
                          borderStrokeWidth: 1.5,
                        ))
                    .toList(),
              ),

            // Checkpoint markers
            if (_currentRoute != null && _currentRoute!.checkpoints.isNotEmpty)
              MarkerLayer(
                markers: _currentRoute!.checkpoints.map((checkpoint) {
                  // Skip if location is at origin (0,0)
                  if (checkpoint.location.latitude == 0 && checkpoint.location.longitude == 0) {
                    return null;
                  }
                  return Marker(
                    point: checkpoint.location,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${checkpoint.index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).whereType<Marker>().toList(),
              ),

            // Current location marker with heading indicator
            if (_currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation!,
                    width: 60,
                    height: 60,
                    child: _buildLocationMarkerWithHeading(),
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

/// Custom painter for heading direction cone
class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Draw a cone/triangle pointing up (north)
    // The transform.rotate in the parent widget will rotate this
    final path = ui.Path();
    path.moveTo(center.dx, center.dy - 28); // Top point (ahead)
    path.lineTo(center.dx - 12, center.dy); // Bottom left
    path.lineTo(center.dx + 12, center.dy); // Bottom right
    path.close();

    canvas.drawPath(path, paint);

    // Draw outline
    final outlinePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
