import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One spoke of the radar chart: a label, its configured colour, and a value.
class RadarPoint {
  final String label;
  final Color color;
  final double value;
  const RadarPoint({required this.label, required this.color, required this.value});
}

/// The octagon: a 4–10 axis radar chart drawn so each axis uses the colour set
/// for it in Settings (coloured vertices + labels).
class OctagonChart extends StatelessWidget {
  final List<RadarPoint> points;

  /// Formats the per-axis value shown under each label (e.g. "12h", "L3").
  final String Function(double value) formatValue;

  const OctagonChart({super.key, required this.points, required this.formatValue});

  @override
  Widget build(BuildContext context) {
    if (points.length < 3) {
      return const Center(child: Text('Need at least 3 axes to draw the octagon.'));
    }
    final theme = Theme.of(context);
    final maxValue = points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);
    final ceiling = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _OctagonPainter(
          points: points,
          ceiling: ceiling,
          gridColor: theme.dividerColor,
          fillColor: theme.colorScheme.primary.withOpacity(0.18),
          lineColor: theme.colorScheme.primary,
          labelStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
          formatValue: formatValue,
        ),
      ),
    );
  }
}

class _OctagonPainter extends CustomPainter {
  final List<RadarPoint> points;
  final double ceiling;
  final Color gridColor;
  final Color fillColor;
  final Color lineColor;
  final TextStyle labelStyle;
  final String Function(double) formatValue;

  _OctagonPainter({
    required this.points,
    required this.ceiling,
    required this.gridColor,
    required this.fillColor,
    required this.lineColor,
    required this.labelStyle,
    required this.formatValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final center = Offset(size.width / 2, size.height / 2);
    // Leave room around the edge for labels.
    final radius = math.min(size.width, size.height) / 2 * 0.66;

    double angle(int i) => -math.pi / 2 + i * 2 * math.pi / n;
    Offset vertex(int i, double r) =>
        center + Offset(math.cos(angle(i)) * r, math.sin(angle(i)) * r);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..color = gridColor.withOpacity(0.6)
      ..strokeWidth = 1;

    // Concentric rings.
    for (final ring in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = vertex(i, radius * ring);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    // Spokes.
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, vertex(i, radius), grid);
    }

    // Data polygon.
    final dataPath = Path();
    final dataPoints = <Offset>[];
    for (var i = 0; i < n; i++) {
      final ratio = (points[i].value / ceiling).clamp(0.0, 1.0);
      final p = vertex(i, radius * ratio);
      dataPoints.add(p);
      i == 0 ? dataPath.moveTo(p.dx, p.dy) : dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = fillColor..style = PaintingStyle.fill);
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Coloured vertices (the Settings colours) + labels.
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(dataPoints[i], 4, Paint()..color = points[i].color);

      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: points[i].label,
              style: labelStyle.copyWith(
                  color: points[i].color, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: '\n${formatValue(points[i].value)}',
              style: labelStyle.copyWith(color: points[i].color.withOpacity(0.85)),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);

      final anchor = vertex(i, radius * 1.16);
      tp.paint(canvas, anchor - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _OctagonPainter old) =>
      old.points != points || old.ceiling != ceiling || old.lineColor != lineColor;
}
