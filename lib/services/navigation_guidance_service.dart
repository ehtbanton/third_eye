import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_info.dart';
import '../models/navigation_checkpoint.dart';
import 'tts_service.dart';
import 'location_service.dart';
import 'heading_service.dart';

class GuidanceState {
  final double remainingDistanceMeters;
  final double remainingTimeSeconds;
  final NavigationCheckpoint? currentCheckpoint;
  final NavigationCheckpoint? nextCheckpoint;
  final int completedCheckpoints;
  final int totalCheckpoints;

  // Heading/direction fields
  final double? headingDelta; // -180 to +180, positive = turn right
  final double? currentHeading; // Device compass heading 0-360
  final double? targetBearing; // Bearing to next checkpoint 0-360
  final double? distanceToNextCheckpoint; // Meters to next checkpoint
  final String? turnInstruction; // "Turn left", "Keep straight", etc.

  GuidanceState({
    required this.remainingDistanceMeters,
    required this.remainingTimeSeconds,
    this.currentCheckpoint,
    this.nextCheckpoint,
    required this.completedCheckpoints,
    required this.totalCheckpoints,
    this.headingDelta,
    this.currentHeading,
    this.targetBearing,
    this.distanceToNextCheckpoint,
    this.turnInstruction,
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
  final HeadingService _headingService;

  RouteInfo? _activeRoute;
  final Set<int> _spokenCheckpoints = {};
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<HeadingData>? _headingSubscription;
  LatLng? _lastKnownLocation;
  double? _currentHeading;

  // Callback for UI updates
  void Function(GuidanceState)? onGuidanceStateChanged;

  // Track last spoken turn instruction to avoid repetition
  String? _lastSpokenTurnInstruction;
  DateTime? _lastTurnInstructionTime;
  static const Duration turnInstructionCooldown = Duration(seconds: 10);

  static const double proximityThresholdMeters = 20.0;
  static const double headingGuidanceThreshold = 30.0; // Speak turn when > 30 degrees off

  NavigationGuidanceService({
    required TtsService ttsService,
    required LocationService locationService,
    required HeadingService headingService,
  })  : _ttsService = ttsService,
        _locationService = locationService,
        _headingService = headingService;

  bool get isActive => _activeRoute != null;

  RouteInfo? get activeRoute => _activeRoute;

  void startGuidance(RouteInfo route) {
    stopGuidance();

    _activeRoute = route;
    _spokenCheckpoints.clear();
    _lastSpokenTurnInstruction = null;
    _lastTurnInstructionTime = null;

    print('Starting navigation guidance with ${route.checkpoints.length} checkpoints');

    // Announce first instruction if available
    if (route.checkpoints.isNotEmpty) {
      final firstCheckpoint = route.checkpoints.first;
      _ttsService.speak('Starting navigation. ${firstCheckpoint.instruction}');
      _spokenCheckpoints.add(firstCheckpoint.index);
    }

    // Subscribe to location updates
    _locationSubscription = _locationService.locationStream.listen((position) {
      _lastKnownLocation = LatLng(position.latitude, position.longitude);
      _checkProximity(_lastKnownLocation!);

      // Use GPS heading as fallback if available and moving
      if (position.heading >= 0 && position.speed > 0.5) {
        _headingService.updateFromGps(position.heading);
      }
    });

    // Subscribe to compass heading updates
    _headingSubscription = _headingService.headingStream.listen((headingData) {
      _currentHeading = headingData.heading;
      _checkHeadingGuidance();
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

  void _checkHeadingGuidance() {
    if (_activeRoute == null || _lastKnownLocation == null || _currentHeading == null) {
      return;
    }

    // Find next unspoken checkpoint
    NavigationCheckpoint? nextCheckpoint;
    for (final checkpoint in _activeRoute!.checkpoints) {
      if (!_spokenCheckpoints.contains(checkpoint.index)) {
        nextCheckpoint = checkpoint;
        break;
      }
    }

    if (nextCheckpoint == null) return;

    // Compute bearing and delta
    final targetBearing = _headingService.computeBearingTo(
      _lastKnownLocation!,
      nextCheckpoint.location,
    );
    final headingDelta = _headingService.computeHeadingDelta(
      _currentHeading!,
      targetBearing,
    );

    // Speak turn instruction if significantly off course
    if (headingDelta.abs() > headingGuidanceThreshold) {
      final instruction = _headingService.getTurnInstruction(headingDelta);

      // Check cooldown to avoid spamming
      final now = DateTime.now();
      final shouldSpeak = _lastSpokenTurnInstruction != instruction ||
          _lastTurnInstructionTime == null ||
          now.difference(_lastTurnInstructionTime!) > turnInstructionCooldown;

      if (shouldSpeak) {
        _ttsService.speak(instruction);
        _lastSpokenTurnInstruction = instruction;
        _lastTurnInstructionTime = now;
        print('Heading guidance: $instruction (delta: ${headingDelta.toStringAsFixed(1)})');
      }
    }

    // Notify UI of state change
    final state = getCurrentState(_lastKnownLocation!);
    onGuidanceStateChanged?.call(state);
  }

  void stopGuidance() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _headingSubscription?.cancel();
    _headingSubscription = null;
    _activeRoute = null;
    _spokenCheckpoints.clear();
    _lastKnownLocation = null;
    _currentHeading = null;
    _lastSpokenTurnInstruction = null;
    _lastTurnInstructionTime = null;
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

    // Compute heading data if available
    double? headingDelta;
    double? targetBearing;
    double? distanceToNext;
    String? turnInstruction;

    if (nextCheckpoint != null && _currentHeading != null) {
      targetBearing = _headingService.computeBearingTo(userLocation, nextCheckpoint.location);
      headingDelta = _headingService.computeHeadingDelta(_currentHeading!, targetBearing);
      distanceToNext = _calculateDistance(userLocation, nextCheckpoint.location);
      turnInstruction = _headingService.getTurnInstruction(headingDelta);
    }

    return GuidanceState(
      remainingDistanceMeters: remainingDistance,
      remainingTimeSeconds: remainingTime,
      currentCheckpoint: _spokenCheckpoints.isNotEmpty
          ? _activeRoute!.checkpoints.where((c) => _spokenCheckpoints.contains(c.index)).lastOrNull
          : null,
      nextCheckpoint: nextCheckpoint,
      completedCheckpoints: _spokenCheckpoints.length,
      totalCheckpoints: _activeRoute!.checkpoints.length,
      headingDelta: headingDelta,
      currentHeading: _currentHeading,
      targetBearing: targetBearing,
      distanceToNextCheckpoint: distanceToNext,
      turnInstruction: turnInstruction,
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
