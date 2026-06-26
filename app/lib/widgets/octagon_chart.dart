import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One spoke of the radar chart: a label, colour, and numeric value.
class RadarPoint {
  final String label;
  final Color color;
  final double value;
  const RadarPoint({required this.label, required this.color, required this.value});
}

/// The octagon: a 4–10 axis radar chart of any per-axis metric (hours / levels).
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
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          dataSets: [
            // Invisible ceiling set so the grid scale stays stable.
            RadarDataSet(
              dataEntries: List.generate(points.length, (_) => RadarEntry(value: ceiling)),
              fillColor: Colors.transparent,
              borderColor: Colors.transparent,
              entryRadius: 0,
              borderWidth: 0,
            ),
            RadarDataSet(
              dataEntries: points.map((p) => RadarEntry(value: p.value)).toList(),
              fillColor: theme.colorScheme.primary.withOpacity(0.25),
              borderColor: theme.colorScheme.primary,
              borderWidth: 2.5,
              entryRadius: 3,
            ),
          ],
          radarBackgroundColor: Colors.transparent,
          radarBorderData: const BorderSide(color: Colors.transparent),
          gridBorderData: BorderSide(color: theme.dividerColor, width: 1),
          tickBorderData: BorderSide(color: theme.dividerColor, width: 1),
          tickCount: 4,
          ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 10),
          titlePositionPercentageOffset: 0.18,
          titleTextStyle: theme.textTheme.labelMedium,
          getTitle: (index, angle) => RadarChartTitle(
            text: '${points[index].label}\n${formatValue(points[index].value)}',
          ),
        ),
      ),
    );
  }
}
