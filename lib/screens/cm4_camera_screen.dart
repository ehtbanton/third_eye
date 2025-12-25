import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/phone_hotspot_service.dart';
import '../services/cm4_stream_service_simple.dart';

/// Simplified CM4 Camera Screen
/// - Enables phone hotspot automatically
/// - Waits for CM4 to connect (static IP)
/// - Shows 3 camera streams
class Cm4CameraScreen extends StatefulWidget {
  const Cm4CameraScreen({Key? key}) : super(key: key);

  @override
  State<Cm4CameraScreen> createState() => _Cm4CameraScreenState();
}

class _Cm4CameraScreenState extends State<Cm4CameraScreen> {
  final PhoneHotspotService _hotspotService = PhoneHotspotService();
  final Cm4StreamService _streamService = Cm4StreamService();

  String _status = 'Initializing...';
  bool _isConnected = false;
  CameraFeed _selectedCamera = CameraFeed.left;

  // Camera stream subscriptions
  final Map<CameraFeed, Uint8List?> _latestFrames = {
    CameraFeed.left: null,
    CameraFeed.right: null,
    CameraFeed.eye: null,
  };

  @override
  void initState() {
    super.initState();
    _autoSetup();
  }

  Future<void> _autoSetup() async {
    try {
      // Step 1: Request permissions
      setState(() => _status = 'Requesting permissions...');
      final permissionsGranted = await _hotspotService.requestPermissions();

      if (!permissionsGranted) {
        setState(() => _status = 'ERROR: Permissions denied');
        return;
      }

      // Step 2: Enable phone hotspot
      setState(() => _status = 'Enabling phone hotspot...');
      final hotspotEnabled = await _hotspotService.enableHotspot();

      if (!hotspotEnabled) {
        setState(() => _status = 'ERROR: Failed to enable hotspot');
        return;
      }

      final config = _hotspotService.getConfiguration();
      setState(() => _status = 'Hotspot enabled: ${config['ssid']}\nWaiting for CM4...');

      // Step 3: Wait for CM4 to connect and be ready
      setState(() => _status = 'Waiting for CM4 at ${_hotspotService.getCm4IpAddress()}...');

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
        setState(() => _status = 'ERROR: CM4 not responding\n\nMake sure CM4 is:\n'
            '1. Powered on\n'
            '2. Configured to connect to: ${config['ssid']}\n'
            '3. Using static IP: ${config['cm4_ip']}');
        return;
      }

      // Step 4: Connect to camera streams
      setState(() => _status = 'CM4 ready! Connecting to cameras...');

      // Subscribe to all camera streams
      for (var camera in CameraFeed.values) {
        _streamService.getImageStream(camera).listen((frame) {
          setState(() {
            _latestFrames[camera] = frame;
          });
        });
      }

      // Connect to all cameras
      await _streamService.connectAll();

      setState(() {
        _status = 'Connected! Streaming...';
        _isConnected = true;
      });
    } catch (e) {
      setState(() => _status = 'ERROR: $e');
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
                  _status = 'Reconnecting...';
                });
                await _streamService.disconnectAll();
                await _autoSetup();
              },
            ),
        ],
      ),
      body: _isConnected ? _buildCameraView() : _buildStatusView(),
      backgroundColor: Colors.black,
    );
  }

  Widget _buildStatusView() {
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
            if (_status.startsWith('ERROR'))
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _status = 'Retrying...');
                    _autoSetup();
                  },
                  child: const Text('Retry'),
                ),
              ),
          ],
        ),
      ),
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
