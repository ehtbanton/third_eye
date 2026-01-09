import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  Completer<void>? _speakCompleter;

  // Callback when speech completes
  void Function()? onSpeechComplete;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Set up completion handler
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakCompleter?.complete();
      _speakCompleter = null;
      onSpeechComplete?.call();
    });

    // Set up start handler
    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    // Set up cancel handler
    _flutterTts.setCancelHandler(() {
      _isSpeaking = false;
      _speakCompleter?.complete();
      _speakCompleter = null;
    });

    // Set up error handler
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      _speakCompleter?.completeError(msg);
      _speakCompleter = null;
      print('TTS Error: $msg');
    });
  }

  Future<void> speak(String text) async {
    _speakCompleter = Completer<void>();
    await _flutterTts.speak(text);
    // Don't await completion here - fire and forget for backwards compatibility
  }

  /// Speak and wait for completion
  Future<void> speakAndWait(String text) async {
    _speakCompleter = Completer<void>();
    await _flutterTts.speak(text);
    await _speakCompleter?.future;
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  void dispose() {
    _flutterTts.stop();
    _isSpeaking = false;
  }
}
