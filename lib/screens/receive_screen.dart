import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/light_sampler.dart';
import '../core/morse_decoder.dart';
import '../theme.dart';
import '../widgets/signal_meter.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  CameraController? _camera;
  final MorseSignalDecoder _decoder = MorseSignalDecoder();
  Timer? _timeoutTimer;

  bool _initializing = true;
  bool _listening = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _decoder.addListener(_onDecoderUpdate);
    _setup();
    // Periodic check so "message complete" / re-sync can fire even between
    // camera frames (e.g. if frames slow down while the app is backgrounded).
    _timeoutTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _decoder.checkForTimeout(DateTime.now());
    });
  }

  Future<void> _setup() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _initializing = false;
        _permissionError = 'Camera permission is required to receive messages.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      final rearCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rearCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      try {
        await controller.setExposureMode(ExposureMode.locked);
        await controller.setFocusMode(FocusMode.locked);
      } catch (_) {
        // Not all devices support locking these — safe to ignore.
      }
      _camera = controller;
      setState(() => _initializing = false);
      _startListening();
    } catch (e) {
      setState(() {
        _initializing = false;
        _permissionError = 'Could not start the camera on this device.';
      });
    }
  }

  void _startListening() {
    final camera = _camera;
    if (camera == null || _listening) return;
    _listening = true;
    camera.startImageStream((image) {
      final brightness = sampleCenterLuminance(image);
      _decoder.addSample(DateTime.now(), brightness);
    });
    setState(() {});
  }

  Future<void> _stopListening() async {
    if (_camera == null || !_listening) return;
    await _camera!.stopImageStream();
    _listening = false;
    setState(() {});
  }

  void _onDecoderUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _decoder.removeListener(_onDecoderUpdate);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Receive'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _decoder.reset(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator(color: AppColors.amber));
    }
    if (_permissionError != null) {
      return _ErrorState(message: _permissionError!, onRetry: _setup);
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(
        child: Text('Camera unavailable', style: TextStyle(color: Colors.white)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(camera),
        // Dim overlay so the crosshair and text panel read clearly.
        Container(color: Colors.black.withOpacity(0.15)),
        Center(
          child: _AimBox(
            color: _statusColor(),
          ),
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _StatusChip(status: _decoder.status),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _DecodedPanel(decoder: _decoder),
        ),
      ],
    );
  }

  Color _statusColor() {
    switch (_decoder.status) {
      case ReceiverStatus.waitingForSignal:
        return AppColors.textSecondary;
      case ReceiverStatus.syncing:
        return AppColors.amber;
      case ReceiverStatus.locked:
        return AppColors.teal;
      case ReceiverStatus.messageComplete:
        return AppColors.teal;
    }
  }
}

class _AimBox extends StatelessWidget {
  const _AimBox({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ReceiverStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      ReceiverStatus.waitingForSignal => (
          'Point camera at the flashing phone',
          AppColors.textSecondary,
          Icons.search_rounded
        ),
      ReceiverStatus.syncing => ('Signal found — syncing\u2026', AppColors.amber, Icons.sync_rounded),
      ReceiverStatus.locked => ('Locked \u2014 decoding', AppColors.teal, Icons.check_circle_outline),
      ReceiverStatus.messageComplete => (
          'Message complete',
          AppColors.teal,
          Icons.done_all_rounded
        ),
    };

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _DecodedPanel extends StatelessWidget {
  const _DecodedPanel({required this.decoder});
  final MorseSignalDecoder decoder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xE6101318),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SignalMeter(samples: decoder.recentBrightness, threshold: decoder.currentThreshold),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Decoded message',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              if (decoder.lockedUnitMs != null)
                Text('~${decoder.lockedUnitMs}ms/unit',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: decoder.decodedText,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  if (decoder.pendingSymbol.isNotEmpty)
                    TextSpan(
                      text: ' ${decoder.pendingSymbol}',
                      style: const TextStyle(
                          color: AppColors.amber,
                          fontSize: 18,
                          fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: AppColors.danger, size: 40),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
