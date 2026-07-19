import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'morse_table.dart';

enum ReceiverStatus {
  waitingForSignal, // not enough contrast yet — probably not aimed at a light
  syncing, // contrast detected, looking for the 3-flash sync pattern
  locked, // sync found, actively decoding letters
  messageComplete, // long silence after at least one decoded letter
}

/// A tiny internal record of one on/off run, used both for the live
/// waveform display and for sync pattern matching.
class _Pulse {
  final bool isOn;
  final int durationMs;
  const _Pulse(this.isOn, this.durationMs);
}

/// Consumes a live stream of (timestamp, brightness) samples from the
/// camera and progressively decodes Morse flashes into text.
///
/// Usage: call [addSample] on every camera frame. Listen via
/// [ChangeNotifier] (this class extends it) for UI updates — read
/// [decodedText], [pendingSymbol], [status], and [recentBrightness] after
/// each notification.
class MorseSignalDecoder extends ChangeNotifier {
  MorseSignalDecoder({this.debounceSamples = 2, this.maxWaveformSamples = 150});

  /// How many consecutive samples must agree before we trust a state flip.
  /// Filters single-frame camera noise without adding much latency.
  final int debounceSamples;

  /// How many brightness samples to keep around for the live waveform UI.
  final int maxWaveformSamples;

  // --- Public read-only state -------------------------------------------------
  String decodedText = '';
  String pendingSymbol = ''; // dots/dashes of the letter currently being built
  ReceiverStatus status = ReceiverStatus.waitingForSignal;
  int? lockedUnitMs;
  final Queue<double> recentBrightness = Queue<double>();
  double currentThreshold = 128;

  // --- Adaptive threshold state ------------------------------------------------
  double _rollingMin = 255;
  double _rollingMax = 0;
  static const double _minContrastToArm = 18; // brightness range needed to trust a signal

  // --- Debounce state -----------------------------------------------------
  bool? _rawState; // last raw thresholded reading
  int _agreeCount = 0;
  bool? _confirmedState; // debounced on/off state actually being timed

  // --- Timing state ---------------------------------------------------------
  DateTime? _stateStartTime;
  DateTime? _lastSampleTime;

  // --- Sync + decode state --------------------------------------------------
  final List<_Pulse> _syncWindow = []; // sliding window of recent pulses pre-lock
  final List<double> _onDurationSamples = []; // used to refine unit estimate

  /// Feed one brightness reading (0-255ish) with its capture time.
  void addSample(DateTime time, double brightness) {
    recentBrightness.addLast(brightness);
    while (recentBrightness.length > maxWaveformSamples) {
      recentBrightness.removeFirst();
    }

    _updateAdaptiveRange(brightness);
    final contrast = _rollingMax - _rollingMin;

    if (contrast < _minContrastToArm) {
      // Not enough light/dark separation — probably not pointed at a torch.
      if (status != ReceiverStatus.locked) {
        status = ReceiverStatus.waitingForSignal;
      }
      _lastSampleTime = time;
      notifyListeners();
      return;
    }

    currentThreshold = (_rollingMin + _rollingMax) / 2;
    final rawIsOn = brightness > currentThreshold;
    _debounceAndProcess(rawIsOn, time);
    _lastSampleTime = time;
  }

  /// Call periodically (e.g. from a UI timer) even if no new camera frame
  /// arrived, so a long silence can still be recognized as "message
  /// complete" or trigger a re-sync without waiting on more frames.
  void checkForTimeout(DateTime now) {
    if (_confirmedState == false && _stateStartTime != null && lockedUnitMs != null) {
      final silence = now.difference(_stateStartTime!).inMilliseconds;
      if (status == ReceiverStatus.locked && silence > lockedUnitMs! * 12) {
        _flushLetter();
        if (decodedText.isNotEmpty) {
          status = ReceiverStatus.messageComplete;
          notifyListeners();
        }
      }
    }
  }

  void reset() {
    decodedText = '';
    pendingSymbol = '';
    status = ReceiverStatus.waitingForSignal;
    lockedUnitMs = null;
    _syncWindow.clear();
    _onDurationSamples.clear();
    _confirmedState = null;
    _rawState = null;
    _stateStartTime = null;
    _rollingMin = 255;
    _rollingMax = 0;
    notifyListeners();
  }

  // --- Internals ---------------------------------------------------------

  void _updateAdaptiveRange(double brightness) {
    // Decay the min/max slowly toward the current reading so the threshold
    // tracks changing ambient light instead of getting stuck on a stale
    // extreme from seconds ago.
    const decay = 0.02;
    _rollingMin = _rollingMin + (brightness - _rollingMin) * decay;
    _rollingMax = _rollingMax + (brightness - _rollingMax) * decay;
    if (brightness < _rollingMin) _rollingMin = brightness;
    if (brightness > _rollingMax) _rollingMax = brightness;
    // Keep the two from collapsing together permanently.
    if (_rollingMax - _rollingMin < 4) {
      _rollingMax = _rollingMin + 4;
    }
  }

  void _debounceAndProcess(bool rawIsOn, DateTime time) {
    if (_rawState == rawIsOn) {
      _agreeCount++;
    } else {
      _rawState = rawIsOn;
      _agreeCount = 1;
    }

    if (_agreeCount < debounceSamples) {
      notifyListeners();
      return; // not confident enough yet to flip
    }

    if (_confirmedState == null) {
      // First confident reading — just start the clock.
      _confirmedState = rawIsOn;
      _stateStartTime = time;
      notifyListeners();
      return;
    }

    if (_confirmedState == rawIsOn) {
      notifyListeners();
      return; // still in the same state, nothing to close out yet
    }

    // State flipped: the previous state just ended — record it as a pulse.
    final durationMs = time.difference(_stateStartTime!).inMilliseconds;
    _onPulseComplete(_Pulse(_confirmedState!, durationMs));

    _confirmedState = rawIsOn;
    _stateStartTime = time;
    notifyListeners();
  }

  void _onPulseComplete(_Pulse pulse) {
    if (status != ReceiverStatus.locked) {
      _tryMatchSync(pulse);
      return;
    }
    _classifyLocked(pulse);
  }

  /// Looks for: on,off,on,off,on,off(long) with the three "on" runs
  /// roughly equal and short, and the final "off" clearly longer than the
  /// gaps between them. This mirrors [encodeMessageToPulses]'s preamble.
  void _tryMatchSync(_Pulse pulse) {
    status = ReceiverStatus.syncing;
    _syncWindow.add(pulse);
    if (_syncWindow.length > 6) {
      _syncWindow.removeAt(0);
    }
    if (_syncWindow.length < 6) return;

    final w = _syncWindow;
    final onDurs = [w[0].durationMs, w[2].durationMs, w[4].durationMs];
    final gapDurs = [w[1].durationMs, w[3].durationMs];
    final tailGap = w[5].durationMs;

    final onAvg = onDurs.reduce((a, b) => a + b) / 3;
    final gapAvg = gapDurs.reduce((a, b) => a + b) / 2;

    final onsConsistent = onDurs.every((d) => (d - onAvg).abs() < onAvg * 0.5);
    final gapsConsistent = gapDurs.every((d) => (d - gapAvg).abs() < gapAvg * 0.6);
    final patternShape = w[0].isOn &&
        !w[1].isOn &&
        w[2].isOn &&
        !w[3].isOn &&
        w[4].isOn &&
        !w[5].isOn;
    final tailIsLong = tailGap > onAvg * 2.5;

    if (patternShape && onsConsistent && gapsConsistent && tailIsLong && onAvg > 20) {
      lockedUnitMs = onAvg.round();
      status = ReceiverStatus.locked;
      pendingSymbol = '';
      decodedText = ''; // fresh message starts after a confirmed sync
      _onDurationSamples
        ..clear()
        ..addAll(onDurs.map((d) => d.toDouble()));
      _syncWindow.clear();
    }
  }

  void _classifyLocked(_Pulse pulse) {
    final unit = lockedUnitMs!;
    if (pulse.isOn) {
      _onDurationSamples.add(pulse.durationMs.toDouble());
      if (_onDurationSamples.length > 12) _onDurationSamples.removeAt(0);
      pendingSymbol += pulse.durationMs > unit * 2 ? '-' : '.';
      return;
    }

    // off pulse: decide what kind of gap this is.
    if (pulse.durationMs < unit * 2) {
      return; // intra-symbol gap — letter isn't finished yet
    } else if (pulse.durationMs < unit * 5.5) {
      _flushLetter();
    } else {
      _flushLetter();
      if (decodedText.isNotEmpty && !decodedText.endsWith(' ')) {
        decodedText += ' ';
      }
    }
  }

  void _flushLetter() {
    if (pendingSymbol.isEmpty) return;
    final letter = kReverseMorseTable[pendingSymbol];
    decodedText += letter ?? '?';
    pendingSymbol = '';
  }
}
