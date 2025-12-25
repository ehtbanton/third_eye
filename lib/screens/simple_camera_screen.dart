import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SimpleCameraScreen extends StatefulWidget {
  const SimpleCameraScreen({Key? key}) : super(key: key);

  @override
  State<SimpleCameraScreen> createState() => _SimpleCameraScreenState();
}

class _SimpleCameraScreenState extends State<SimpleCameraScreen> {
  static const String host = 'thirdeye.local';
  static const leftUrl = 'http://$host:8081/stream';
  static const rightUrl = 'http://$host:8082/stream';
  static const eyeUrl = 'http://$host:8083/stream';

  bool _showEyeCamera = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Status bar
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black87,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Third Eye',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  IconButton(
                    icon: Icon(
                      _showEyeCamera ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _showEyeCamera = !_showEyeCamera;
                      });
                    },
                  ),
                ],
              ),
            ),

            // Camera views
            Expanded(
              child: _showEyeCamera
                  ? _buildEyeView()
                  : _buildStereoView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStereoView() {
    return Row(
      children: [
        Expanded(child: _buildCameraView(leftUrl, 'Left')),
        Expanded(child: _buildCameraView(rightUrl, 'Right')),
      ],
    );
  }

  Widget _buildEyeView() {
    return _buildCameraView(eyeUrl, 'Eye Camera');
  }

  Widget _buildCameraView(String url, String label) {
    return Container(
      margin: const EdgeInsets.all(2),
      color: Colors.grey[900],
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
