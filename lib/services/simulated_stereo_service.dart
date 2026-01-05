import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

class SimulatedStereoService {
  Player? _player;
  VideoController? videoController;

  File? _tempVideoFile;

  bool get isConnected => _player != null;

  static const String defaultAsset = 'assets/videos/sim_sbs.mp4';

  Future<bool> connect({String assetPath = defaultAsset, bool loop = true}) async {
    try {
      _player ??= Player();
      videoController ??= VideoController(_player!);

      final dir = await getTemporaryDirectory();
      final safeName = assetPath.split('/').last;
      final file = File('${dir.path}/$safeName');

      if (!await file.exists()) {
        final ByteData data = await rootBundle.load(assetPath);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }

      _tempVideoFile = file;

      await _player!.open(
        Media(file.path),
        play: true,
      );

      if (loop) {
        _player!.stream.completed.listen((done) async {
          if (done && _player != null) {
            await _player!.seek(Duration.zero);
            await _player!.play();
          }
        });
      }

      debugPrint('SimulatedStereoService: playing file ${file.path}');
      return true;
    } catch (e) {
      debugPrint('SimulatedStereoService connect failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}

    _player = null;
    videoController = null;

    // try { await _tempVideoFile?.delete(); } catch (_) {}
    _tempVideoFile = null;
  }

  Future<Uint8List?> captureFrame() async {
    try {
      if (_player == null) return null;
      return await _player!.screenshot();
    } catch (e) {
      debugPrint('SimulatedStereoService screenshot failed: $e');
      return null;
    }
  }
}
