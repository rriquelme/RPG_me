import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models.dart';

/// The octagon: an 8-axis radar chart of your life levels.
class OctagonChart extends StatelessWidget {
  final List<AxisStat> stats;

  const OctagonChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.length < 3) {
      return const Center(child: Text('Need at least 3 axes to draw the octagon.'));
    }

    final theme = Theme.of(context);
    final maxLevel = stats.map((s) => s.level).fold<int>(0, (a, b) => a > b ? a : b);
    // Keep the web from collapsing when everything is still level 0/1.
    final ceiling = (maxLevel < 5 ? 5 : maxLevel + 1).toDouble();

    return AspectRatio(
      aspectRatio: 1,
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          dataSets: [
            // Invisible ceiling set so the grid scale stays stable.
            RadarDataSet(
              dataEntries: List.generate(
                stats.length,
                (_) => RadarEntry(value: ceiling),
              ),
              fillColor: Colors.transparent,
              borderColor: Colors.transparent,
              entryRadius: 0,
              borderWidth: 0,
            ),
            // The real data.
            RadarDataSet(
              dataEntries:
                  stats.map((s) => RadarEntry(value: s.level.toDouble())).toList(),
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
          tickCount: ceiling.toInt().clamp(1, 6),
          ticksTextStyle:
              const TextStyle(color: Colors.transparent, fontSize: 10),
          titlePositionPercentageOffset: 0.18,
          titleTextStyle: theme.textTheme.labelMedium,
          getTitle: (index, angle) => RadarChartTitle(
            text: '${stats[index].label}\nL${stats[index].level}',
          ),
        ),
      ),
    );
  }
}
