import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_info.dart';
import '../models/navigation_checkpoint.dart';
import 'tts_service.dart';
import 'location_service.dart';

class GuidanceState {
  final double remainingDistanceMeters;
  final double remainingTimeSeconds;
  final NavigationCheckpoint? currentCheckpoint;
  final NavigationCheckpoint? nextCheckpoint;
  final int completedCheckpoints;
  final int totalCheckpoints;

  GuidanceState({
    required this.remainingDistanceMeters,
    required this.remainingTimeSeconds,
    this.currentCheckpoint,
    this.nextCheckpoint,
    required this.completedCheckpoints,
    required this.totalCheckpoints,
  });

  String get formattedRemainingDistance {
    if (remainingDistanceMeters < 1000) {
      return '${remainingDistanceMeters.toStringAsFixed(0)} m';
    } else {
      return '${(remainingDistanceMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  String get formattedRemainingTime {
    final minutes = remainingTimeSeconds / 60;
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = (minutes % 60).round();
      return '$hours h $remainingMinutes min';
    }
  }
}

class NavigationGuidanceService {
  final TtsService _ttsService;
  final LocationService _locationService;

  RouteInfo? _activeRoute;
  final Set<int> _spokenCheckpoints = {};
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _lastKnownLocation;

  // Callback for UI updates
  void Function(GuidanceState)? onGuidanceStateChanged;

  static const double proximityThresholdMeters = 20.0;

  NavigationGuidanceService({
    required TtsService ttsService,
    required LocationService locationService,
  })  : _ttsService = ttsService,
        _locationService = locationService;

  bool get isActive => _activeRoute != null;

  RouteInfo? get activeRoute => _activeRoute;

  void startGuidance(RouteInfo route) {
    stopGuidance();

    _activeRoute = route;
    _spokenCheckpoints.clear();

    print('Starting navigation guidance with ${route.checkpoints.length} checkpoints');

    // Announce first instruction if available
    if (route.checkpoints.isNotEmpty) {
      final firstCheckpoint = route.checkpoints.first;
      _ttsService.speak('Starting navigation. ${firstCheckpoint.instruction}');
      _spokenCheckpoints.add(firstCheckpoint.index);
    }

    _locationSubscription = _locationService.locationStream.listen((position) {
      _lastKnownLocation = LatLng(position.latitude, position.longitude);
      _checkProximity(_lastKnownLocation!);
    });
  }

  void _checkProximity(LatLng userLocation) {
    if (_activeRoute == null) return;

    for (final checkpoint in _activeRoute!.checkpoints) {
      if (_spokenCheckpoints.contains(checkpoint.index)) continue;

      final distance = _calculateDistance(userLocation, checkpoint.location);
      if (distance <= proximityThresholdMeters) {
        _speakInstruction(checkpoint);
        _spokenCheckpoints.add(checkpoint.index);
      }
    }

    // Notify UI of state change
    final state = getCurrentState(userLocation);
    onGuidanceStateChanged?.call(state);
  }

  void _speakInstruction(NavigationCheckpoint checkpoint) {
    print('Speaking checkpoint ${checkpoint.index}: ${checkpoint.instruction}');
    _ttsService.speak(checkpoint.instruction);
  }

  void stopGuidance() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _activeRoute = null;
    _spokenCheckpoints.clear();
    _lastKnownLocation = null;
    print('Navigation guidance stopped');
  }

  GuidanceState getCurrentState(LatLng userLocation) {
    if (_activeRoute == null) {
      return GuidanceState(
        remainingDistanceMeters: 0,
        remainingTimeSeconds: 0,
        completedCheckpoints: 0,
        totalCheckpoints: 0,
      );
    }

    // Find next unspoken checkpoint
    NavigationCheckpoint? nextCheckpoint;
    for (final checkpoint in _activeRoute!.checkpoints) {
      if (!_spokenCheckpoints.contains(checkpoint.index)) {
        nextCheckpoint = checkpoint;
        break;
      }
    }

    // Calculate remaining distance (simple approximation: distance to destination)
    final remainingDistance = _calculateDistance(userLocation, _activeRoute!.destination);

    // Estimate remaining time based on walking speed (~1.4 m/s or 5 km/h)
    final remainingTime = remainingDistance / 1.4;

    return GuidanceState(
      remainingDistanceMeters: remainingDistance,
      remainingTimeSeconds: remainingTime,
      currentCheckpoint: _spokenCheckpoints.isNotEmpty
          ? _activeRoute!.checkpoints.where((c) => _spokenCheckpoints.contains(c.index)).lastOrNull
          : null,
      nextCheckpoint: nextCheckpoint,
      completedCheckpoints: _spokenCheckpoints.length,
      totalCheckpoints: _activeRoute!.checkpoints.length,
    );
  }

  double _calculateDistance(LatLng from, LatLng to) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, from, to);
  }

  void dispose() {
    stopGuidance();
  }
}
