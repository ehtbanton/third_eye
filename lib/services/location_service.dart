import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  bool _autoFollow = true;
  bool _isInitialized = false;

  final _locationController = StreamController<Position>.broadcast();

  Position? get currentPosition => _currentPosition;
  bool get autoFollow => _autoFollow;
  bool get isInitialized => _isInitialized;
  Stream<Position> get locationStream => _locationController.stream;

  Future<bool> initialize() async {
    try {
      // Request location permission
      final permission = await Permission.location.request();
      if (!permission.isGranted) {
        print('Location permission denied');
        return false;
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return false;
      }

      // Get initial position
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      );

      // Start listening to position updates
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((Position position) {
        _currentPosition = position;
        _locationController.add(position);
      }, onError: (error) {
        print('Location stream error: $error');
      });

      _isInitialized = true;
      print('LocationService initialized successfully');
      return true;
    } catch (e) {
      print('Failed to initialize LocationService: $e');
      return false;
    }
  }

  Future<Position?> getCurrentLocation() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return _currentPosition;
    } catch (e) {
      print('Failed to get current location: $e');
      return _currentPosition;
    }
  }

  void setAutoFollow(bool value) {
    _autoFollow = value;
  }

  void dispose() {
    _positionSubscription?.cancel();
    _locationController.close();
  }
}
