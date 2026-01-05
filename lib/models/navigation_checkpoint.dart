import 'package:latlong2/latlong.dart';

class NavigationCheckpoint {
  final LatLng location;
  final String instruction;
  final double distanceMeters;
  final int index;
  final String? streetName;
  final String maneuver;

  NavigationCheckpoint({
    required this.location,
    required this.instruction,
    required this.distanceMeters,
    required this.index,
    this.streetName,
    required this.maneuver,
  });

  factory NavigationCheckpoint.fromAzureMapsInstruction(
    Map<String, dynamic> json,
    int index,
  ) {
    final point = json['point'] as Map<String, dynamic>?;
    final lat = (point?['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (point?['longitude'] as num?)?.toDouble() ?? 0.0;

    return NavigationCheckpoint(
      location: LatLng(lat, lng),
      instruction: json['message'] as String? ?? '',
      distanceMeters: (json['routeOffsetInMeters'] as num?)?.toDouble() ?? 0.0,
      index: index,
      streetName: json['street'] as String?,
      maneuver: json['maneuver'] as String? ?? 'UNKNOWN',
    );
  }

  @override
  String toString() {
    return 'NavigationCheckpoint($index: $instruction at $location)';
  }
}
