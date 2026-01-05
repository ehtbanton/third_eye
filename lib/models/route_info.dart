import 'package:latlong2/latlong.dart';
import 'navigation_checkpoint.dart';

class RouteInfo {
  final List<LatLng> routePoints;
  final double distanceMeters;
  final double durationSeconds;
  final String summary;
  final DateTime timestamp;
  final LatLng destination;
  final List<NavigationCheckpoint> checkpoints;

  RouteInfo({
    required this.routePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.summary,
    required this.timestamp,
    required this.destination,
    this.checkpoints = const [],
  });

  factory RouteInfo.fromAzureMapsResponse(Map<String, dynamic> json) {
    final routes = json['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No routes found in response');
    }

    final route = routes[0] as Map<String, dynamic>;
    final summary = route['summary'] as Map<String, dynamic>?;
    final legs = route['legs'] as List<dynamic>?;
    final guidance = route['guidance'] as Map<String, dynamic>?;

    // Extract route points from legs
    final List<LatLng> points = [];
    if (legs != null) {
      for (final leg in legs) {
        final legPoints = leg['points'] as List<dynamic>?;
        if (legPoints != null) {
          for (final point in legPoints) {
            points.add(LatLng(
              (point['latitude'] as num).toDouble(),
              (point['longitude'] as num).toDouble(),
            ));
          }
        }
      }
    }

    final distanceMeters = (summary?['lengthInMeters'] as num?)?.toDouble() ?? 0.0;
    final durationSeconds = (summary?['travelTimeInSeconds'] as num?)?.toDouble() ?? 0.0;

    // Create summary text
    final distanceKm = distanceMeters / 1000;
    final durationMinutes = durationSeconds / 60;
    final summaryText = '${distanceKm.toStringAsFixed(1)} km, ${durationMinutes.toStringAsFixed(0)} min';

    // Parse guidance instructions from route-level guidance
    final List<NavigationCheckpoint> checkpoints = [];
    final instructions = guidance?['instructions'] as List<dynamic>?;
    if (instructions != null) {
      int checkpointIndex = 0;
      for (final instruction in instructions) {
        if (instruction != null && instruction is Map<String, dynamic>) {
          checkpoints.add(NavigationCheckpoint.fromAzureMapsInstruction(
            instruction,
            checkpointIndex++,
          ));
        }
      }
    }

    return RouteInfo(
      routePoints: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      summary: summaryText,
      timestamp: DateTime.now(),
      destination: points.isNotEmpty ? points.last : const LatLng(0, 0),
      checkpoints: checkpoints,
    );
  }

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  String get formattedDuration {
    final minutes = durationSeconds / 60;
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = (minutes % 60).round();
      return '$hours h $remainingMinutes min';
    }
  }
}
