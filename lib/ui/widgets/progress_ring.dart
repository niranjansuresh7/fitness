import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular progress indicator that keeps drawing past 100%.
///
/// Going over the goal is meaningful information — for water it is fine, for a
/// sodium limit it is not — so overflow is drawn as a second, darker arc rather
/// than being clipped away.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 180,
    this.strokeWidth = 14,
    this.trackColor,
    this.child,
  });

  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.isFinite ? progress : 0.0,
          color: color,
          strokeWidth: strokeWidth,
          trackColor: trackColor ?? scheme.surfaceContainerHighest,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final Color trackColor;

  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(strokeWidth / 2);

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);

    if (progress <= 0) return;

    final Paint arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final double firstLap = progress.clamp(0.0, 1.0);
    canvas.drawArc(arcRect, _startAngle, math.pi * 2 * firstLap, false, arc);

    if (progress > 1.0) {
      final Paint over = Paint()
        ..color = Color.alphaBlend(Colors.black.withValues(alpha: 0.35), color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final double extra = (progress - 1.0).clamp(0.0, 1.0);
      canvas.drawArc(arcRect, _startAngle, math.pi * 2 * extra, false, over);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor;
}
