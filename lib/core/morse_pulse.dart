import 'morse_table.dart';

/// A single on/off segment of the transmission.
/// [isOn] = true means the torch should be lit for [durationMs].
class MorsePulse {
  final bool isOn;
  final int durationMs;
  const MorsePulse(this.isOn, this.durationMs);
}

/// Encodes [text] into a list of timed pulses ready to be played back by
/// toggling the torch. [unitMs] is the duration of one Morse "dit" —
/// everything else (dash, gaps) is a multiple of it.
///
/// Standard timing ratios (Morse convention):
///   dot            = 1 unit  (on)
///   dash           = 3 units (on)
///   intra-letter gap = 1 unit  (off, between symbols of the same letter)
///   inter-letter gap = 3 units (off, between letters)
///   word gap         = 7 units (off, between words)
///
/// A short sync preamble (three quick flashes) is prepended so a receiver
/// can find the start of the transmission and estimate the unit duration.
List<MorsePulse> encodeMessageToPulses(String text, {int unitMs = 150}) {
  final pulses = <MorsePulse>[];

  // --- Sync preamble: three short flashes, then a pause ~5x as long.
  for (int i = 0; i < 3; i++) {
    pulses.add(MorsePulse(true, unitMs));
    pulses.add(MorsePulse(false, unitMs));
  }
  pulses.removeLast();
  pulses.add(MorsePulse(false, unitMs * 5)); // marks "message starts now"

  final chars = text.toUpperCase().trim().split('');
  for (int i = 0; i < chars.length; i++) {
    final char = chars[i];

    if (char == ' ') {
      pulses.add(MorsePulse(false, unitMs * 7));
      continue;
    }

    final code = kMorseTable[char];
    if (code == null) continue; // skip unsupported characters

    for (int s = 0; s < code.length; s++) {
      final symbol = code[s];
      pulses.add(MorsePulse(true, symbol == '.' ? unitMs : unitMs * 3));
      if (s != code.length - 1) {
        pulses.add(MorsePulse(false, unitMs)); // intra-letter gap
      }
    }

    // Decide the gap that follows this letter.
    final isLastChar = i == chars.length - 1;
    final nextIsSpace = !isLastChar && chars[i + 1] == ' ';
    if (!isLastChar && !nextIsSpace) {
      pulses.add(MorsePulse(false, unitMs * 3)); // inter-letter gap
    }
  }

  // --- Trailing pause: the receiver treats a long silence after the last
  // letter as "transmission complete" — no extra pulses needed to mark it.
  pulses.add(MorsePulse(false, unitMs * 8));

  return pulses;
}

/// Total playback duration of a pulse sequence, in milliseconds.
int totalDurationMs(List<MorsePulse> pulses) =>
    pulses.fold(0, (sum, p) => sum + p.durationMs);
