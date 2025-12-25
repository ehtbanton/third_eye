import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/cm4_ble_service.dart';
import '../services/cm4_stream_service.dart';

/// Auto-connecting camera view screen
/// Automatically discovers CM4, connects via BLE, and shows camera streams
class CameraViewScreen extends StatefulWidget {
  const CameraViewScreen({Key? key}) : super(key: key);

  @override
  State<CameraViewScreen> createState() => _CameraViewScreenState();
}

class _CameraViewScreenState extends State<CameraViewScreen> {
  final Cm4BleService _bleService = Cm4BleService();
  final Cm4StreamService _streamService = Cm4StreamService();

  String _status = 'Initializing...';
  bool _isConnected = false;
  CameraFeed _selectedCamera = CameraFeed.left;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    setState(() => _status = 'Requesting permissions...');

    // Request permissions
    await _requestPermissions();

    setState(() => _status = 'Scanning for CM4...');

    // Scan for CM4
    try {
      final devices = await _bleService.scanForCM4(timeout: const Duration(seconds: 10));

      if (devices.isEmpty) {
        setState(() => _status = 'CM4 not found. Retrying...');
        await Future.delayed(const Duration(seconds: 2));
        return _autoConnect(); // Retry
      }

      setState(() => _status = 'Found CM4! Connecting...');

      // Connect to first device
      final success = await _bleService.connect(devices.first.device);

      if (!success) {
        setState(() => _status = 'BLE connection failed. Retrying...');
        await Future.delayed(const Duration(seconds: 2));
        return _autoConnect();
      }

      setState(() => _status = 'BLE connected! Starting cameras...');

      // Start WiFi and cameras via BLE
      await _bleService.startWiFi();
      await Future.delayed(const Duration(seconds: 3));
      await _bleService.startCamera();

      setState(() => _status = 'Connecting to video streams...');
      await Future.delayed(const Duration(seconds: 5)); // Wait for WiFi connection

      // Connect to camera streams
      await _streamService.connectAll();

      setState(() {
        _status = 'Connected! Viewing cameras...';
        _isConnected = true;
      });
    } catch (e) {
      setState(() => _status = 'Error: $e\nRetrying...');
      await Future.delayed(const Duration(seconds: 3));
      _autoConnect();
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
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
              onPressed: () {
                setState(() => _isConnected = false);
                _streamService.disconnectAll();
                _bleService.disconnect();
                _autoConnect();
              },
            ),
        ],
      ),
      body: _isConnected ? _buildCameraView() : _buildConnectingView(),
    );
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            _status,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          const Text(
            '1. Power on CM4\n2. Wait for StereoPi_5G WiFi\n3. App will auto-connect',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return Column(
      children: [
        // Status bar
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.green.shade900,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text('Connected', style: TextStyle(color: Colors.white)),
              const Spacer(),
              Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),

        // Camera selector
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SegmentedButton<CameraFeed>(
            segments: const [
              ButtonSegment(value: CameraFeed.left, label: Text('Left'), icon: Icon(Icons.camera)),
              ButtonSegment(value: CameraFeed.right, label: Text('Right'), icon: Icon(Icons.camera)),
              ButtonSegment(value: CameraFeed.eye, label: Text('Eye'), icon: Icon(Icons.remove_red_eye)),
            ],
            selected: {_selectedCamera},
            onSelectionChanged: (Set<CameraFeed> selection) {
              setState(() => _selectedCamera = selection.first);
            },
          ),
        ),

        // Camera stream
        Expanded(
          child: StreamBuilder<Uint8List>(
            stream: _streamService.getImageStream(_selectedCamera),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                );
              }
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Waiting for video...'),
                  ],
                ),
              );
            },
          ),
        ),

        // FPS indicator
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'FPS: ${_streamService.getFps(_selectedCamera).toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _streamService.dispose();
    _bleService.dispose();
    super.dispose();
  }
}
