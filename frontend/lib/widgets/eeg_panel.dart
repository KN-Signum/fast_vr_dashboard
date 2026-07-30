import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../theme/app_style.dart';

const double _kPanelWidth = 320;

class EegPanel extends StatelessWidget {
  const EegPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final latest = eeg.latest;
    final channels = eeg.getChannels();

    return Container(
      width: _kPanelWidth,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            fresh: eeg.hasFreshData,
            samplingRate: latest?.samplingRate ?? 250,
            channelCount: latest?.channels.length ?? 0,
            sampleCount: latest?.sampleCount ?? 0,
          ),
          Expanded(
            child: latest == null
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: channels.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final channel = channels[index];
                      return _ChannelChart(
                        channel: channel,
                        samples: eeg.samplesForChannel(channel),
                        samplingRate: latest.samplingRate,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool fresh;
  final int samplingRate;
  final int channelCount;
  final int sampleCount;

  const _Header({
    required this.fresh,
    required this.samplingRate,
    required this.channelCount,
    required this.sampleCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: AppColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'SYGNAŁY EEG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(
                label: fresh ? 'DANE AKTYWNE' : 'BRAK ŚWIEŻYCH DANYCH',
                active: fresh,
              ),
              _StatusPill(label: '$samplingRate Hz'),
              _StatusPill(label: '$channelCount kan.'),
              if (sampleCount > 0) _StatusPill(label: '$sampleCount próbek'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool? active;

  const _StatusPill({required this.label, this.active});

  @override
  Widget build(BuildContext context) {
    final color = switch (active) {
      true => Colors.greenAccent.shade400,
      false => Colors.orangeAccent.shade200,
      null => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChannelChart extends StatelessWidget {
  final String channel;
  final List<double> samples;
  final int samplingRate;

  const _ChannelChart({
    required this.channel,
    required this.samples,
    required this.samplingRate,
  });

  @override
  Widget build(BuildContext context) {
    final centered = _center(samples);
    final duration = samplingRate > 0 ? samples.length / samplingRate : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  channel,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${duration.toStringAsFixed(1)} s · µV',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 105,
            child: centered.isEmpty
                ? Center(
                    child: Text(
                      'Oczekiwanie na próbki',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                      ),
                    ),
                  )
                : LineChart(_chartData(centered), duration: Duration.zero),
          ),
        ],
      ),
    );
  }

  List<double> _center(List<double> values) {
    if (values.isEmpty) return const [];
    final mean = values.reduce((a, b) => a + b) / values.length;
    return values.map((value) => value - mean).toList(growable: false);
  }

  LineChartData _chartData(List<double> values) {
    final maxAbs = values.fold<double>(
      0,
      (current, value) => math.max(current, value.abs()),
    );
    final extent = math.max(maxAbs * 1.1, 1.0);

    return LineChartData(
      minY: -extent,
      maxY: extent,
      minX: 0,
      maxX: math.max(values.length - 1, 1).toDouble(),
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: extent,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: extent,
            getTitlesWidget: (value, _) => Text(
              value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 7, color: Colors.black45),
            ),
          ),
        ),
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: values
              .asMap()
              .entries
              .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
              .toList(growable: false),
          isCurved: false,
          color: Colors.blue.shade600,
          barWidth: 1.1,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
      lineTouchData: const LineTouchData(enabled: false),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              color: Colors.grey.shade400,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              'Oczekiwanie na dane EEG',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
