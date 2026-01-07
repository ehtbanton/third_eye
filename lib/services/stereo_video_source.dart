import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:image/image.dart' as img;

/// Represents a stereo frame pair (left and right images).
class StereoFramePair {
  final Uint8List leftImage;   // JPEG bytes for left image
  final Uint8List rightImage;  // JPEG bytes for right image
  final int width;             // Width of each image
  final int height;            // Height of each image

  StereoFramePair({
    required this.leftImage,
    required this.rightImage,
    required this.width,
    required this.height,
  });
}

/// Abstract interface for any stereo frame source.
/// Allows depth map service to work with different stereo sources.
abstract class StereoFrameSource {
  Future<StereoFramePair?> captureStereoPair();
  void dispose();
}

/// Virtual stereo video source from local side-by-side (SBS) video file.
///
/// SBS format: Two horizontally squashed views stitched together.
/// Each view is squashed 2x horizontally, so the combined video has
/// the same aspect ratio as either original view.
///
/// Example: Original 1920x1080 stereo pair becomes 1920x1080 SBS video
/// where left half (0-959) contains squashed left view and
/// right half (960-1919) contains squashed right view.
class StereoVideoSource implements StereoFrameSource {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _videoPath;
  bool _hasFrames = false;
  int _videoWidth = 0;
  int _videoHeight = 0;

  final _connectionStateController = StreamController<bool>.broadcast();

  /// Stream of connection/initialization state
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Whether the video source is initialized
  bool get isInitialized => _isInitialized;

  /// Whether the video is currently playing
  bool get isPlaying => _isPlaying;

  /// Whether we have received video frames (ready for capture)
  bool get hasFrames => _hasFrames;

  /// Video width in pixels
  int get videoWidth => _videoWidth;

  /// Video height in pixels
  int get videoHeight => _videoHeight;

  /// Video controller for display widget
  VideoController? get videoController => _videoController;

  /// Current video path
  String? get videoPath => _videoPath;

  /// Initialize the video source with a local SBS video file.
  ///
  /// [videoPath] - Path to the SBS video file (local file or asset)
  Future<bool> initialize(String videoPath) async {
    if (_isInitialized) {
      await dispose();
    }

    _videoPath = videoPath;
    _hasFrames = false;
    _videoWidth = 0;
    _videoHeight = 0;
    debugPrint('StereoVideoSource: Initializing with $videoPath');

    try {
      _player = Player();
      _videoController = VideoController(_player!);

      // Listen to player state
      _player!.stream.playing.listen((playing) {
        _isPlaying = playing;
        debugPrint('StereoVideoSource: Playing: $playing');
      });

      _player!.stream.error.listen((error) {
        debugPrint('StereoVideoSource: Error: $error');
      });

      _player!.stream.completed.listen((completed) {
        if (completed) {
          debugPrint('StereoVideoSource: Playback completed, looping...');
          _player?.seek(Duration.zero);
          _player?.play();
        }
      });

      // Listen for video dimensions - this tells us when frames are available
      _player!.stream.width.listen((width) {
        if (width != null && width > 0) {
          _videoWidth = width;
          debugPrint('StereoVideoSource: Video width: $width');
          _checkFramesReady();
        }
      });

      _player!.stream.height.listen((height) {
        if (height != null && height > 0) {
          _videoHeight = height;
          debugPrint('StereoVideoSource: Video height: $height');
          _checkFramesReady();
        }
      });

      // Open the video file
      await _player!.open(
        Media(videoPath),
        play: false, // Don't auto-play
      );

      _isInitialized = true;
      _connectionStateController.add(true);
      debugPrint('StereoVideoSource: Initialized successfully');
      return true;
    } catch (e, stack) {
      debugPrint('StereoVideoSource: Failed to initialize: $e');
      debugPrint('StereoVideoSource: Stack: $stack');
      _isInitialized = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  void _checkFramesReady() {
    if (_videoWidth > 0 && _videoHeight > 0 && !_hasFrames) {
      _hasFrames = true;
      debugPrint('StereoVideoSource: Frames ready - ${_videoWidth}x$_videoHeight');
    }
  }

  /// Start video playback.
  Future<void> play() async {
    if (_player != null && _isInitialized) {
      await _player!.play();
    }
  }

  /// Pause video playback.
  Future<void> pause() async {
    if (_player != null) {
      await _player!.pause();
    }
  }

  /// Seek to a specific position.
  Future<void> seek(Duration position) async {
    if (_player != null) {
      await _player!.seek(position);
    }
  }

  /// Get current playback position.
  Duration get position => _player?.state.position ?? Duration.zero;

  /// Get total duration.
  Duration get duration => _player?.state.duration ?? Duration.zero;

  /// Capture the current frame and split it into left/right stereo pair.
  ///
  /// The SBS video has both views horizontally squashed and stitched:
  /// - Left half: squashed left view
  /// - Right half: squashed right view
  ///
  /// This method splits the frame at the midpoint and returns both halves.
  @override
  Future<StereoFramePair?> captureStereoPair() async {
    if (_player == null || !_isInitialized) {
      debugPrint('StereoVideoSource: Cannot capture - not initialized');
      return null;
    }

    if (!_hasFrames) {
      debugPrint('StereoVideoSource: Cannot capture - no frames available yet');
      return null;
    }

    if (!_isPlaying) {
      debugPrint('StereoVideoSource: Cannot capture - video not playing');
      return null;
    }

    try {
      // Capture the full SBS frame (with retry)
      Uint8List? screenshot;
      for (int attempt = 0; attempt < 3; attempt++) {
        screenshot = await _player!.screenshot();
        if (screenshot != null && screenshot.isNotEmpty) {
          break;
        }
        debugPrint('StereoVideoSource: Screenshot attempt ${attempt + 1} returned null, retrying...');
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (screenshot == null || screenshot.isEmpty) {
        debugPrint('StereoVideoSource: Screenshot returned null after retries');
        return null;
      }

      debugPrint('StereoVideoSource: Got screenshot of ${screenshot.length} bytes');

      // Decode the JPEG image
      final fullImage = img.decodeImage(screenshot);
      if (fullImage == null) {
        debugPrint('StereoVideoSource: Failed to decode screenshot');
        return null;
      }

      final fullWidth = fullImage.width;
      final fullHeight = fullImage.height;
      final halfWidth = fullWidth ~/ 2;

      debugPrint('StereoVideoSource: Full image: ${fullWidth}x$fullHeight, splitting at $halfWidth');

      // Split at midpoint
      // Left half: x = 0 to halfWidth-1
      final leftImage = img.copyCrop(fullImage, x: 0, y: 0, width: halfWidth, height: fullHeight);
      // Right half: x = halfWidth to fullWidth-1
      final rightImage = img.copyCrop(fullImage, x: halfWidth, y: 0, width: halfWidth, height: fullHeight);

      // Encode back to JPEG for consistent format
      final leftJpeg = Uint8List.fromList(img.encodeJpg(leftImage, quality: 90));
      final rightJpeg = Uint8List.fromList(img.encodeJpg(rightImage, quality: 90));

      debugPrint('StereoVideoSource: Stereo pair captured - left: ${leftJpeg.length} bytes, right: ${rightJpeg.length} bytes');

      return StereoFramePair(
        leftImage: leftJpeg,
        rightImage: rightJpeg,
        width: halfWidth,
        height: fullHeight,
      );
    } catch (e, stack) {
      debugPrint('StereoVideoSource: Failed to capture stereo pair: $e');
      debugPrint('StereoVideoSource: Stack: $stack');
      return null;
    }
  }

  /// Capture the raw full SBS frame without splitting.
  Future<Uint8List?> captureRawFrame() async {
    if (_player == null || !_isInitialized) {
      return null;
    }
    return await _player!.screenshot();
  }

  @override
  Future<void> dispose() async {
    debugPrint('StereoVideoSource: Disposing...');
    _isInitialized = false;
    _isPlaying = false;
    _connectionStateController.add(false);

    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;

    await _connectionStateController.close();
    debugPrint('StereoVideoSource: Disposed');
  }
}
