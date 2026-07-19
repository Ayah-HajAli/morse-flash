import 'dart:collection';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Live scrolling brightness waveform with the current adaptive threshold
/// drawn as a horizontal line, so the user can see the receiver "seeing"
/// the flash in real time.
class SignalMeter extends StatelessWidget {
  const SignalMeter({
    super.key,
    required this.samples,
    required this.threshold,
  });

  final Queue<double> samples;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      width: double.infinity,
      child: CustomPaint(
        painter: _MeterPainter(samples: samples, threshold: threshold),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({required this.samples, required this.threshold});

  final Queue<double> samples;
  final double threshold;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = AppColors.surfaceHigh;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(16)),
      bgPaint,
    );

    if (samples.isEmpty) return;

    final list = samples.toList();
    final n = list.length;
    final dx = size.width / (n > 1 ? n - 1 : 1);

    final path = Path();
    for (int i = 0; i < n; i++) {
      final v = (list[i].clamp(0, 255)) / 255.0;
      final y = size.height - (v * size.height);
      final x = i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = AppColors.amberBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final threshY = size.height - ((threshold.clamp(0, 255)) / 255.0 * size.height);
    final threshPaint = Paint()
      ..color = AppColors.teal.withOpacity(0.7)
      ..strokeWidth = 1;
    final dashWidth = 6.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, threshY),
        Offset(startX + dashWidth, threshY),
        threshPaint,
      );
      startX += dashWidth * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) => true;
}
