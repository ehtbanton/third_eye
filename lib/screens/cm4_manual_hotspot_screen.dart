import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cm4_stream_service_simple.dart';

/// CM4 Camera Screen with Manual Hotspot Setup
/// User manually enables hotspot, app connects to CM4
class Cm4ManualHotspotScreen extends StatefulWidget {
  const Cm4ManualHotspotScreen({Key? key}) : super(key: key);

  @override
  State<Cm4ManualHotspotScreen> createState() => _Cm4ManualHotspotScreenState();
}

class _Cm4ManualHotspotScreenState extends State<Cm4ManualHotspotScreen> {
  final Cm4StreamService _streamService = Cm4StreamService();

  // Hotspot configuration
  static const String requiredSsid = 'ThirdEye_Hotspot';
  static const String requiredPassword = 'thirdeye123';
  static const String cm4Ip = '192.168.43.100';

  bool _setupComplete = false;
  bool _isConnected = false;
  String _status = 'Ready to connect';
  CameraFeed _selectedCamera = CameraFeed.left;

  // Camera stream frames
  final Map<CameraFeed, Uint8List?> _latestFrames = {
    CameraFeed.left: null,
    CameraFeed.right: null,
    CameraFeed.eye: null,
  };

  @override
  void initState() {
    super.initState();
  }

  Future<void> _startConnection() async {
    setState(() {
      _status = 'Checking for CM4...';
      _setupComplete = true;
    });

    try {
      // Health check - wait for CM4 to be reachable
      bool cm4Ready = false;
      int attempts = 0;
      const maxAttempts = 30; // 30 seconds

      while (!cm4Ready && attempts < maxAttempts) {
        cm4Ready = await _streamService.healthCheck();
        if (!cm4Ready) {
          await Future.delayed(const Duration(seconds: 1));
          attempts++;
          setState(() => _status = 'Waiting for CM4... ($attempts/$maxAttempts)');
        }
      }

      if (!cm4Ready) {
        setState(() {
          _status = 'CM4 not responding!\n\nMake sure:\n'
              '• CM4 is powered on\n'
              '• CM4 connects to: $requiredSsid\n'
              '• CM4 uses static IP: $cm4Ip\n'
              '• Hotspot is enabled on this phone';
          _setupComplete = false;
        });
        return;
      }

      // Subscribe to camera streams
      setState(() => _status = 'CM4 found! Connecting to cameras...');

      for (var camera in CameraFeed.values) {
        _streamService.getImageStream(camera).listen((frame) {
          if (mounted) {
            setState(() {
              _latestFrames[camera] = frame;
            });
          }
        });
      }

      // Connect to all cameras
      await _streamService.connectAll();

      setState(() {
        _status = 'Connected! Streaming...';
        _isConnected = true;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _setupComplete = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Third Eye - CM4 Cameras'),
        backgroundColor: Colors.black87,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() {
                  _isConnected = false;
                  _setupComplete = false;
                  _status = 'Reconnecting...';
                });
                await _streamService.disconnectAll();
                await _startConnection();
              },
            ),
        ],
      ),
      body: _isConnected ? _buildCameraView() : _buildSetupView(),
      backgroundColor: Colors.black,
    );
  }

  Widget _buildSetupView() {
    if (_setupComplete) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              if (_status.contains('not responding'))
                Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _setupComplete = false;
                        _status = 'Ready to connect';
                      });
                    },
                    child: const Text('Back to Setup'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Setup Instructions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Step 1
          _buildStep(
            number: '1',
            title: 'Enable Phone Hotspot',
            description: 'Open your phone settings and enable WiFi hotspot with these exact settings:',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _buildConfigItem('SSID (Network Name)', requiredSsid, canCopy: true),
                _buildConfigItem('Password', requiredPassword, canCopy: true),
                _buildConfigItem('Band', '5GHz (recommended)'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    // Open hotspot settings
                    const platform = MethodChannel('app.channel.hotspot');
                    try {
                      platform.invokeMethod('openHotspotSettings');
                    } catch (e) {
                      // Fallback - just show message
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please manually open Settings → Hotspot & tethering'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Hotspot Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Step 2
          _buildStep(
            number: '2',
            title: 'Configure CM4',
            description: 'Make sure your CM4 is configured to:',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _buildBullet('Connect to WiFi: $requiredSsid'),
                _buildBullet('Use static IP: $cm4Ip'),
                _buildBullet('Run camera server on ports 8081-8083'),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => _buildConfigDialog(),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                  label: const Text('View CM4 Configuration'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Step 3
          _buildStep(
            number: '3',
            title: 'Connect',
            description: 'Once your hotspot is enabled and CM4 is powered on:',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                    child: const Text(
                      'Connect to CM4',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String description,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
          content,
        ],
      ),
    );
  }

  Widget _buildConfigItem(String label, String value, {bool canCopy = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(color: Colors.grey[400]),
          ),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (canCopy) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  color: Colors.blue,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied: $value')),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.blue, fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigDialog() {
    return AlertDialog(
      title: const Text('CM4 Configuration'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add to /etc/wpa_supplicant/wpa_supplicant.conf:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              child: const Text(
                'network={\n'
                '  ssid="ThirdEye_Hotspot"\n'
                '  psk="thirdeye123"\n'
                '  key_mgmt=WPA-PSK\n'
                '}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add to /etc/dhcpcd.conf:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              child: const Text(
                'interface wlan0\n'
                'static ip_address=192.168.43.100/24\n'
                'static routers=192.168.43.1\n'
                'static domain_name_servers=192.168.43.1',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildCameraView() {
    return Column(
      children: [
        // Camera selector
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCameraButton(CameraFeed.left, 'Left', Icons.chevron_left),
              _buildCameraButton(CameraFeed.eye, 'Eye', Icons.visibility),
              _buildCameraButton(CameraFeed.right, 'Right', Icons.chevron_right),
            ],
          ),
        ),

        // Main camera view
        Expanded(
          child: Center(
            child: _latestFrames[_selectedCamera] != null
                ? Image.memory(
                    _latestFrames[_selectedCamera]!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  )
                : const CircularProgressIndicator(),
          ),
        ),

        // FPS and status bar
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusChip(
                'Left: ${_streamService.getFps(CameraFeed.left).toStringAsFixed(1)} fps',
                _latestFrames[CameraFeed.left] != null,
              ),
              _buildStatusChip(
                'Eye: ${_streamService.getFps(CameraFeed.eye).toStringAsFixed(1)} fps',
                _latestFrames[CameraFeed.eye] != null,
              ),
              _buildStatusChip(
                'Right: ${_streamService.getFps(CameraFeed.right).toStringAsFixed(1)} fps',
                _latestFrames[CameraFeed.right] != null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraButton(CameraFeed camera, String label, IconData icon) {
    final isSelected = _selectedCamera == camera;
    return ElevatedButton.icon(
      onPressed: () => setState(() => _selectedCamera = camera),
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[800],
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatusChip(String text, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[900] : Colors.red[900],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _streamService.dispose();
    super.dispose();
  }
}
