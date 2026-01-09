import 'dart:async';
import 'dart:collection';
import 'tts_service.dart';

enum AudioPriority {
  critical, // "Stop! Car ahead" - immediate interrupt
  warning, // "Person on your left" - high priority queue
  navigation, // "Turn left" - normal queue
  ambient // Periodic updates - lowest priority
}

class PrioritizedMessage {
  final String text;
  final AudioPriority priority;
  final DateTime createdAt;
  final Duration maxAge;

  PrioritizedMessage({
    required this.text,
    required this.priority,
    Duration? maxAge,
  })  : createdAt = DateTime.now(),
        maxAge = maxAge ?? const Duration(seconds: 5);

  bool get isExpired => DateTime.now().difference(createdAt) > maxAge;

  int get priorityValue {
    switch (priority) {
      case AudioPriority.critical:
        return 0;
      case AudioPriority.warning:
        return 1;
      case AudioPriority.navigation:
        return 2;
      case AudioPriority.ambient:
        return 3;
    }
  }
}

class AudioPriorityService {
  final TtsService _ttsService;

  // Priority queue (sorted by priority, then by creation time)
  final SplayTreeSet<PrioritizedMessage> _queue = SplayTreeSet<PrioritizedMessage>(
    (a, b) {
      final priorityCompare = a.priorityValue.compareTo(b.priorityValue);
      if (priorityCompare != 0) return priorityCompare;
      return a.createdAt.compareTo(b.createdAt);
    },
  );

  // Deduplication tracking
  final Map<String, DateTime> _recentMessages = {};
  static const Duration deduplicationWindow = Duration(seconds: 2);

  // Rate limiting
  DateTime? _lastNavigationSpeech;
  DateTime? _lastWarningSpeech;
  static const Duration navigationCooldown = Duration(seconds: 5);
  static const Duration warningCooldown = Duration(seconds: 3);

  bool _isProcessing = false;
  Timer? _processTimer;

  bool get isSpeaking => _ttsService.isSpeaking;

  AudioPriorityService({required TtsService ttsService}) : _ttsService = ttsService {
    // Set up completion callback to process next in queue
    _ttsService.onSpeechComplete = _processQueue;
  }

  /// Add a message to the queue with given priority
  Future<void> speak(String text, AudioPriority priority) async {
    // Check for duplicates
    if (_isDuplicate(text)) {
      print('AudioPriority: Skipping duplicate message: $text');
      return;
    }

    // Check rate limits
    if (!_passesRateLimit(priority)) {
      print('AudioPriority: Rate limited ($priority): $text');
      return;
    }

    final message = PrioritizedMessage(text: text, priority: priority);

    // Critical messages interrupt immediately
    if (priority == AudioPriority.critical) {
      await _interruptAndSpeak(message);
      return;
    }

    // Add to queue
    _queue.add(message);
    _trackMessage(text);
    _updateRateLimit(priority);

    // Start processing if not already
    _scheduleProcessing();
  }

  /// Interrupt current speech for critical message
  Future<void> _interruptAndSpeak(PrioritizedMessage message) async {
    print('AudioPriority: CRITICAL interrupt: ${message.text}');
    await _ttsService.stop();
    _trackMessage(message.text);
    _updateRateLimit(message.priority);
    await _ttsService.speak(message.text);
  }

  /// Process the queue
  void _processQueue() {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;

    // Remove expired messages
    _queue.removeWhere((m) => m.isExpired);

    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    // Get highest priority message
    final message = _queue.first;
    _queue.remove(message);

    print('AudioPriority: Speaking (${message.priority}): ${message.text}');
    _ttsService.speak(message.text).then((_) {
      _isProcessing = false;
      // Next message will be processed via onSpeechComplete callback
    });
  }

  void _scheduleProcessing() {
    if (_processTimer?.isActive ?? false) return;
    if (_ttsService.isSpeaking) return;

    // Small delay to batch messages that come in rapid succession
    _processTimer = Timer(const Duration(milliseconds: 100), () {
      _processQueue();
    });
  }

  bool _isDuplicate(String text) {
    final lastTime = _recentMessages[text];
    if (lastTime == null) return false;
    return DateTime.now().difference(lastTime) < deduplicationWindow;
  }

  void _trackMessage(String text) {
    _recentMessages[text] = DateTime.now();

    // Clean up old entries
    final cutoff = DateTime.now().subtract(deduplicationWindow);
    _recentMessages.removeWhere((_, time) => time.isBefore(cutoff));
  }

  bool _passesRateLimit(AudioPriority priority) {
    final now = DateTime.now();

    switch (priority) {
      case AudioPriority.critical:
        return true; // Never rate limited
      case AudioPriority.warning:
        if (_lastWarningSpeech == null) return true;
        return now.difference(_lastWarningSpeech!) > warningCooldown;
      case AudioPriority.navigation:
        if (_lastNavigationSpeech == null) return true;
        return now.difference(_lastNavigationSpeech!) > navigationCooldown;
      case AudioPriority.ambient:
        // Ambient follows navigation rate limit
        if (_lastNavigationSpeech == null) return true;
        return now.difference(_lastNavigationSpeech!) > navigationCooldown;
    }
  }

  void _updateRateLimit(AudioPriority priority) {
    final now = DateTime.now();
    switch (priority) {
      case AudioPriority.critical:
      case AudioPriority.warning:
        _lastWarningSpeech = now;
        break;
      case AudioPriority.navigation:
      case AudioPriority.ambient:
        _lastNavigationSpeech = now;
        break;
    }
  }

  /// Clear the queue
  void clear() {
    _queue.clear();
    _processTimer?.cancel();
    _isProcessing = false;
  }

  /// Stop current speech and clear queue
  Future<void> stop() async {
    clear();
    await _ttsService.stop();
  }

  void dispose() {
    _processTimer?.cancel();
    clear();
  }
}
