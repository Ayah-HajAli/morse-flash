import 'dart:async';
import 'package:torch_light/torch_light.dart';
import 'morse_pulse.dart';

enum TransmitState { idle, transmitting, finished, cancelled, error }

/// Drives the device torch through a sequence of [MorsePulse]s and exposes
/// live progress so the UI can animate in sync.
class MorseTransmitter {
  bool _cancelled = false;
  bool _running = false;

  bool get isRunning => _running;

  /// Plays [pulses] on the torch.
  /// [onProgress] fires on every pulse with (index, pulse, elapsedMs, totalMs).
  /// [onScreenFlash] optionally mirrors on/off state for a screen-flash fallback.
  Future<TransmitState> play(
    List<MorsePulse> pulses, {
    void Function(int index, MorsePulse pulse, int elapsedMs, int totalMs)? onProgress,
    void Function(bool isOn)? onScreenFlash,
  }) async {
    if (_running) return TransmitState.error;
    _running = true;
    _cancelled = false;

    final total = totalDurationMs(pulses);
    int elapsed = 0;

    try {
      for (int i = 0; i < pulses.length; i++) {
        if (_cancelled) {
          await _safeOff();
          _running = false;
          return TransmitState.cancelled;
        }

        final pulse = pulses[i];
        if (pulse.isOn) {
          await TorchLight.enableTorch();
        } else {
          await TorchLight.disableTorch();
        }
        onScreenFlash?.call(pulse.isOn);
        onProgress?.call(i, pulse, elapsed, total);

        await Future.delayed(Duration(milliseconds: pulse.durationMs));
        elapsed += pulse.durationMs;
      }
      await _safeOff();
      onScreenFlash?.call(false);
      _running = false;
      return TransmitState.finished;
    } catch (_) {
      await _safeOff();
      _running = false;
      return TransmitState.error;
    }
  }

  void cancel() => _cancelled = true;

  Future<void> _safeOff() async {
    try {
      await TorchLight.disableTorch();
    } catch (_) {
      // ignore — best effort cleanup
    }
  }
}
