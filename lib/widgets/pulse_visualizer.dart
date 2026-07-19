import 'package:flutter/material.dart';
import '../core/morse_pulse.dart';
import '../theme.dart';

/// Draws the whole pulse sequence as a horizontal timeline of blocks
/// (wide = dash, narrow = dot, gaps in between), with a progress line
/// sweeping across as the message transmits.
class PulseVisualizer extends StatelessWidget {
  const PulseVisualizer({
    super.key,
    required this.pulses,
    required this.progress, // 0.0 - 1.0
    required this.isActive,
  });

  final List<MorsePulse> pulses;
  final double progress;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: CustomPaint(
        painter: _PulsePainter(
          pulses: pulses,
          progress: progress,
          isActive: isActive,
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.pulses,
    required this.progress,
    required this.isActive,
  });

  final List<MorsePulse> pulses;
  final double progress;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final total = pulses.fold<int>(0, (sum, p) => sum + p.durationMs);
    if (total == 0) return;

    final onPaint = Paint()..color = AppColors.amber;
    final onPaintDim = Paint()..color = AppColors.amber.withOpacity(0.25);
    const barHeight = 28.0;
    final top = (size.height - barHeight) / 2;

    double x = 0;
    final progressX = progress * size.width;

    for (final pulse in pulses) {
      final w = (pulse.durationMs / total) * size.width;
      if (pulse.isOn) {
        final passed = isActive && x + w <= progressX;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, w, barHeight),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, passed ? onPaintDim : onPaint);
      }
      x += w;
    }

    if (isActive) {
      final lineP = Paint()
        ..color = AppColors.teal
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        lineP,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isActive != isActive;
  }
}
