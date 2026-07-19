import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';
import '../core/morse_pulse.dart';
import '../core/morse_transmitter.dart';
import '../theme.dart';
import '../widgets/pulse_visualizer.dart';

class TransmitScreen extends StatefulWidget {
  const TransmitScreen({super.key});

  @override
  State<TransmitScreen> createState() => _TransmitScreenState();
}

class _TransmitScreenState extends State<TransmitScreen> {
  final _controller = TextEditingController();
  final _transmitter = MorseTransmitter();

  double _speedUnitMs = 150;
  bool _screenFlashFallback = false;
  bool _screenIsLit = false;
  bool _torchAvailable = true;

  List<MorsePulse> _pulses = [];
  double _progress = 0;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkTorch();
  }

  Future<void> _checkTorch() async {
    try {
      final available = await TorchLight.isTorchAvailable();
      if (mounted) setState(() => _torchAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _torchAvailable = false);
    }
  }

  @override
  void dispose() {
    _transmitter.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final pulses = encodeMessageToPulses(text, unitMs: _speedUnitMs.round());
    setState(() {
      _pulses = pulses;
      _isSending = true;
      _progress = 0;
      _error = null;
    });

    final result = await _transmitter.play(
      pulses,
      onProgress: (index, pulse, elapsedMs, totalMs) {
        if (!mounted) return;
        setState(() => _progress = totalMs == 0 ? 0 : elapsedMs / totalMs);
      },
      onScreenFlash: _screenFlashFallback
          ? (isOn) {
              if (mounted) setState(() => _screenIsLit = isOn);
            }
          : null,
    );

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _progress = 1;
      _screenIsLit = false;
      if (result == TransmitState.error) {
        _error = "Couldn't access the flashlight on this device.";
      }
    });
  }

  void _cancel() {
    _transmitter.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = _screenFlashFallback && _screenIsLit
        ? Colors.white
        : AppColors.bg;

    return Scaffold(
      backgroundColor: backdrop,
      appBar: AppBar(title: const Text('Send')),
      body: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 40),
          color: backdrop,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_torchAvailable)
                  _Banner(
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    text:
                        'No flashlight detected on this device. Try the screen-flash fallback below.',
                  ),
                if (_error != null)
                  _Banner(icon: Icons.error_outline, color: AppColors.danger, text: _error!),
                const SizedBox(height: 8),
                Text('Message', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  enabled: !_isSending,
                  maxLines: 3,
                  maxLength: 140,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Type something to flash out in Morse\u2026',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Speed',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Row(
                  children: [
                    const Text('Slow', style: TextStyle(color: AppColors.textSecondary)),
                    Expanded(
                      child: Slider(
                        value: _speedUnitMs,
                        min: 80,
                        max: 300,
                        divisions: 22,
                        activeColor: AppColors.amber,
                        onChanged: _isSending
                            ? null
                            : (v) => setState(() => _speedUnitMs = v),
                      ),
                    ),
                    const Text('Fast', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.amber,
                  title: const Text('Also flash the screen'),
                  subtitle: const Text(
                    'Useful for testing without a second device, or if torch access fails.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  value: _screenFlashFallback,
                  onChanged: _isSending
                      ? null
                      : (v) => setState(() => _screenFlashFallback = v),
                ),
                const SizedBox(height: 12),
                if (_pulses.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: PulseVisualizer(
                      pulses: _pulses,
                      progress: _progress,
                      isActive: _isSending,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSending ? null : _send,
                        icon: Icon(_isSending
                            ? Icons.flash_on_rounded
                            : Icons.flash_on_outlined),
                        label: Text(_isSending ? 'Sending\u2026' : 'Flash it'),
                      ),
                    ),
                    if (_isSending) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _cancel,
                        child: const Text('Stop'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
