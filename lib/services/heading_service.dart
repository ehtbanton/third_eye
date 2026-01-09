import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';

enum HeadingSource { magnetometer, gps }

class HeadingData {
  final double heading; // 0-360 compass bearing
  final double? accuracy; // Heading accuracy if available
  final HeadingSource source;

  HeadingData({
    required this.heading,
    this.accuracy,
    required this.source,
  });
}

class HeadingService {
  StreamSubscription<CompassEvent>? _compassSubscription;
  final StreamController<HeadingData> _headingController =
      StreamController<HeadingData>.broadcast();

  double? _lastHeading;
  double? _lastAccuracy;
  bool _isInitialized = false;

  Stream<HeadingData> get headingStream => _headingController.stream;
  double? get currentHeading => _lastHeading;
  bool get isAvailable => _isInitialized && _lastHeading != null;

  Future<void> initialize() async {
    // Check if compass is available on this device
    final isSupported = await FlutterCompass.events != null;
    if (!isSupported) {
      print('HeadingService: Compass not available on this device');
      return;
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _lastHeading = event.heading!;
        _lastAccuracy = event.accuracy;
        _isInitialized = true;

        _headingController.add(HeadingData(
          heading: event.heading!,
          accuracy: event.accuracy,
          source: HeadingSource.magnetometer,
        ));
      }
    });

    print('HeadingService: Initialized with magnetometer');
  }

  /// Compute bearing from current position to target using Haversine formula
  /// Returns bearing in degrees (0-360, where 0 = North, 90 = East)
  double computeBearingTo(LatLng current, LatLng target) {
    final lat1 = current.latitudeInRad;
    final lat2 = target.latitudeInRad;
    final dLon = target.longitudeInRad - current.longitudeInRad;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    var bearing = atan2(y, x);
    bearing = bearing * 180 / pi; // Convert to degrees
    bearing = (bearing + 360) % 360; // Normalize to 0-360

    return bearing;
  }

  /// Compute heading delta (how much to turn)
  /// Returns value from -180 to +180
  /// Positive = turn right, Negative = turn left
  double computeHeadingDelta(double currentHeading, double targetBearing) {
    var delta = targetBearing - currentHeading;

    // Normalize to -180 to +180
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }

    return delta;
  }

  /// Get turn instruction based on heading delta
  String getTurnInstruction(double headingDelta) {
    final absDelta = headingDelta.abs();

    if (absDelta < 15) {
      return 'Keep straight';
    } else if (absDelta < 30) {
      return headingDelta > 0 ? 'Slight right' : 'Slight left';
    } else if (absDelta < 60) {
      return headingDelta > 0 ? 'Turn right' : 'Turn left';
    } else if (absDelta < 150) {
      return headingDelta > 0 ? 'Sharp right' : 'Sharp left';
    } else {
      return 'Turn around';
    }
  }

  /// Update heading from GPS (fallback when stationary and GPS heading available)
  void updateFromGps(double gpsHeading) {
    // Only use GPS heading if magnetometer is unavailable
    if (_lastHeading == null) {
      _lastHeading = gpsHeading;
      _headingController.add(HeadingData(
        heading: gpsHeading,
        accuracy: null,
        source: HeadingSource.gps,
      ));
    }
  }

  void dispose() {
    _compassSubscription?.cancel();
    _headingController.close();
    print('HeadingService: Disposed');
  }
}
