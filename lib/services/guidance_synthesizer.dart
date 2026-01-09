import 'navigation_guidance_service.dart';
import 'safe_path_service.dart';
import 'obstacle_fusion_service.dart';
import 'audio_priority_service.dart';

/// Synthesizes guidance from multiple sources into prioritized voice output.
///
/// Priority order:
/// 1. Critical obstacle → "Stop! Car ahead"
/// 2. Path blocked → "Path blocked, veer left"
/// 3. Heading correction → "Turn right"
/// 4. Clear + on track → "Keep straight"
/// 5. Checkpoint approach → "Turn left in 10 meters"
class GuidanceSynthesizer {
  final AudioPriorityService _audioService;

  // Track last announced guidance to avoid repetition
  String? _lastGuidance;
  DateTime? _lastGuidanceTime;
  static const Duration guidanceRepeatCooldown = Duration(seconds: 8);

  GuidanceSynthesizer({required AudioPriorityService audioService})
      : _audioService = audioService;

  /// Synthesize and announce guidance from all sources
  void synthesize({
    required GuidanceState? navigationState,
    required SafePathResult? safePathResult,
    required List<ObstacleWarning> obstacles,
  }) {
    // Priority 1: Critical obstacles
    final criticalObstacles = obstacles.where((o) => o.isCritical).toList();
    if (criticalObstacles.isNotEmpty) {
      final warning = criticalObstacles.first;
      _audioService.speak(warning.announcement, AudioPriority.critical);
      return; // Critical takes full priority, stop processing
    }

    // Priority 2: Path blocked
    if (safePathResult?.safety == PathSafety.blocked) {
      final action = safePathResult!.suggestedAction ?? 'Stop, path blocked';
      _speakIfNew(action, AudioPriority.warning);
      return;
    }

    // Priority 3: Non-critical obstacles (announce one at a time)
    if (obstacles.isNotEmpty) {
      final warning = obstacles.first;
      _audioService.speak(warning.announcement, AudioPriority.warning);
      // Continue processing other guidance types
    }

    // Priority 4: Path caution (veer instructions)
    if (safePathResult?.safety == PathSafety.caution &&
        safePathResult?.suggestedAction != null) {
      _speakIfNew(safePathResult!.suggestedAction!, AudioPriority.navigation);
    }

    // Priority 5: Heading correction (only if significantly off course)
    if (navigationState?.headingDelta != null &&
        navigationState!.headingDelta!.abs() > 30) {
      final turnInstruction = navigationState.turnInstruction;
      if (turnInstruction != null && turnInstruction != 'Keep straight') {
        _speakIfNew(turnInstruction, AudioPriority.navigation);
      }
    }

    // Priority 6: Clear path confirmation (occasionally)
    if (safePathResult?.safety == PathSafety.clear &&
        obstacles.isEmpty &&
        (navigationState?.headingDelta?.abs() ?? 0) < 15) {
      _speakIfNew('Clear ahead', AudioPriority.ambient);
    }
  }

  /// Announce checkpoint approach
  void announceCheckpoint(String instruction, double? distanceMeters) {
    String message;
    if (distanceMeters != null && distanceMeters < 30) {
      message = 'In ${distanceMeters.round()} meters, $instruction';
    } else {
      message = instruction;
    }
    _audioService.speak(message, AudioPriority.navigation);
  }

  /// Generate combined status for UI display
  SynthesizedGuidance getDisplayGuidance({
    required GuidanceState? navigationState,
    required SafePathResult? safePathResult,
    required List<ObstacleWarning> obstacles,
  }) {
    // Determine primary message
    String primaryMessage;
    GuidanceUrgency urgency;

    final criticalObstacles = obstacles.where((o) => o.isCritical).toList();

    if (criticalObstacles.isNotEmpty) {
      primaryMessage = criticalObstacles.first.announcement;
      urgency = GuidanceUrgency.critical;
    } else if (safePathResult?.safety == PathSafety.blocked) {
      primaryMessage = safePathResult!.suggestedAction ?? 'Path blocked';
      urgency = GuidanceUrgency.warning;
    } else if (obstacles.isNotEmpty) {
      primaryMessage = obstacles.first.announcement;
      urgency = GuidanceUrgency.warning;
    } else if (safePathResult?.safety == PathSafety.caution) {
      primaryMessage = safePathResult!.suggestedAction ?? 'Caution';
      urgency = GuidanceUrgency.caution;
    } else if (navigationState?.turnInstruction != null &&
        navigationState!.headingDelta!.abs() > 20) {
      primaryMessage = navigationState.turnInstruction!;
      urgency = GuidanceUrgency.navigation;
    } else {
      primaryMessage = 'Clear ahead';
      urgency = GuidanceUrgency.clear;
    }

    // Secondary info
    String? secondaryMessage;
    if (navigationState?.nextCheckpoint != null) {
      final dist = navigationState!.distanceToNextCheckpoint;
      if (dist != null && dist < 50) {
        secondaryMessage = '${dist.round()}m to ${navigationState.nextCheckpoint!.instruction}';
      }
    }

    return SynthesizedGuidance(
      primaryMessage: primaryMessage,
      secondaryMessage: secondaryMessage,
      urgency: urgency,
      headingDelta: navigationState?.headingDelta,
      pathSafety: safePathResult?.safety,
      obstacleCount: obstacles.length,
    );
  }

  void _speakIfNew(String message, AudioPriority priority) {
    final now = DateTime.now();

    // Check if this is the same message as last time
    if (_lastGuidance == message &&
        _lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!) < guidanceRepeatCooldown) {
      return; // Skip duplicate
    }

    _lastGuidance = message;
    _lastGuidanceTime = now;
    _audioService.speak(message, priority);
  }

  /// Reset state (e.g., when navigation restarts)
  void reset() {
    _lastGuidance = null;
    _lastGuidanceTime = null;
  }
}

enum GuidanceUrgency {
  critical, // Red - stop immediately
  warning, // Orange - obstacle nearby
  caution, // Yellow - attention needed
  navigation, // Blue - turn instruction
  clear, // Green - all clear
}

class SynthesizedGuidance {
  final String primaryMessage;
  final String? secondaryMessage;
  final GuidanceUrgency urgency;
  final double? headingDelta;
  final PathSafety? pathSafety;
  final int obstacleCount;

  SynthesizedGuidance({
    required this.primaryMessage,
    this.secondaryMessage,
    required this.urgency,
    this.headingDelta,
    this.pathSafety,
    required this.obstacleCount,
  });
}
