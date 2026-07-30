import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../theme/app_style.dart';

const double _kPanelWidth = 320;
const int _kMaxRenderedSamples = 1000;

FlTitlesData _timeTitles({String leftSuffix = ''}) {
  return FlTitlesData(
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 34,
        getTitlesWidget: (value, _) => Text(
          '${value.toStringAsFixed(0)}$leftSuffix',
          style: const TextStyle(fontSize: 7, color: Colors.black45),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 18,
        interval: 10,
        getTitlesWidget: (value, _) => Text(
          '${value.toStringAsFixed(0)} s',
          style: const TextStyle(fontSize: 7, color: Colors.black45),
        ),
      ),
    ),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

class EegPanel extends StatelessWidget {
  const EegPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final latest = eeg.latest;
    final channels = eeg.getChannels();
    final visibleChannels = channels
        .where(eeg.isChannelEnabled)
        .toList(growable: false);

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
          if (latest != null) ...[
            _ChannelSelector(channels: channels, eeg: eeg),
            _ErdChart(
              history: eeg.alphaErdHistory,
              channels: visibleChannels,
              status: latest.erdStatus,
              baselineSeconds: latest.erdBaselineSeconds,
              baselineTargetSeconds: latest.erdBaselineTargetSeconds,
            ),
          ],
          Expanded(
            child: latest == null
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: visibleChannels.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final channel = visibleChannels[index];
                      return _ChannelChart(
                        channel: channel,
                        samples: eeg.displaySamplesForChannel(channel),
                        samplingRate: latest.samplingRate,
                        quality: eeg.qualityForChannel(channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelSelector extends StatelessWidget {
  final List<String> channels;
  final EegProvider eeg;

  const _ChannelSelector({required this.channels, required this.eeg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: channels
            .map(
              (channel) => FilterChip(
                label: Text(channel),
                selected: eeg.isChannelEnabled(channel),
                onSelected: (_) => eeg.toggleChannel(channel),
                selectedColor: AppColors.primary.withValues(alpha: 0.18),
                checkmarkColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ErdChart extends StatelessWidget {
  static const _colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.brown,
    Colors.pink,
  ];

  final List<EegErdPoint> history;
  final List<String> channels;
  final String status;
  final int baselineSeconds;
  final int baselineTargetSeconds;

  const _ErdChart({
    required this.history,
    required this.channels,
    required this.status,
    required this.baselineSeconds,
    required this.baselineTargetSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final newest = history.isEmpty ? null : history.last.timestamp;
    final lines = newest == null
        ? const <LineChartBarData>[]
        : channels.indexed
              .map((entry) {
                final (index, channel) = entry;
                final spots = history
                    .where((point) => point.values.containsKey(channel))
                    .map(
                      (point) => FlSpot(
                        point.timestamp.difference(newest).inMilliseconds /
                            1000,
                        point.values[channel]!,
                      ),
                    )
                    .toList(growable: false);
                return LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: _colors[index % _colors.length],
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                );
              })
              .where((line) => line.spots.isNotEmpty)
              .toList(growable: false);

    return Container(
      height: 170,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Znormalizowana zmiana alfa',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      status == 'collecting'
                          ? 'Zbieranie linii bazowej alfa: '
                                '$baselineSeconds/$baselineTargetSeconds s'
                          : status == 'waiting'
                          ? 'Linia bazowa alfa rozpocznie się z sesją'
                          : status == 'ready'
                          ? 'Wskaźnik gotowy — oczekiwanie na dane'
                          : 'Zmiana alfa nie jest dostępna',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                      ),
                    ),
                  )
                : LineChart(_erdChartData(lines), duration: Duration.zero),
          ),
        ],
      ),
    );
  }

  LineChartData _erdChartData(List<LineChartBarData> lines) {
    final values = lines.expand((line) => line.spots.map((spot) => spot.y));
    final oldestSecond = lines
        .expand((line) => line.spots.map((spot) => spot.x))
        .fold<double>(0, math.min);
    final maxAbs = values.fold<double>(
      0,
      (current, value) => math.max(current, value.abs()),
    );
    final extent = math.max(maxAbs * 1.1, 10.0);

    return LineChartData(
      minX: math.min(oldestSecond, -1),
      maxX: 0,
      minY: -extent,
      maxY: extent,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        verticalInterval: 10,
        horizontalInterval: extent,
      ),
      titlesData: _timeTitles(leftSuffix: '%'),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      lineBarsData: lines,
      lineTouchData: const LineTouchData(enabled: false),
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
  final EegChannelQuality quality;

  const _ChannelChart({
    required this.channel,
    required this.samples,
    required this.samplingRate,
    required this.quality,
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
              if (quality.hasWarning) ...[
                _QualityBadge(quality: quality),
                const SizedBox(width: 6),
              ],
              Text(
                '${duration.toStringAsFixed(1)} s · 1–40 Hz · µV',
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
                : LineChart(
                    _chartData(centered, samplingRate),
                    duration: Duration.zero,
                  ),
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

  LineChartData _chartData(List<double> values, int samplingRate) {
    final extent = _robustExtent(values);

    final spots = _sampleSpots(values, samplingRate);
    final durationSeconds = samplingRate > 0
        ? (values.length - 1) / samplingRate
        : 0.0;

    return LineChartData(
      minY: -extent,
      maxY: extent,
      minX: -math.max(
        durationSeconds,
        samplingRate > 0 ? 1.0 / samplingRate : 1.0,
      ),
      maxX: 0,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: extent,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
      ),
      titlesData: _timeTitles(),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
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

  double _robustExtent(List<double> values) {
    final step = math.max(1, (values.length / _kMaxRenderedSamples).ceil());
    final magnitudes = <double>[
      for (var index = 0; index < values.length; index += step)
        values[index].abs(),
    ]..sort();
    final percentileIndex = math.min(
      magnitudes.length - 1,
      (magnitudes.length * 0.99).floor(),
    );
    return math.max(magnitudes[percentileIndex] * 1.2, 1.0);
  }

  List<FlSpot> _sampleSpots(List<double> values, int samplingRate) {
    if (values.isEmpty || samplingRate <= 0) return const [];
    final step = math.max(1, (values.length / _kMaxRenderedSamples).ceil());
    final lastIndex = values.length - 1;
    final spots = <FlSpot>[];

    for (var index = 0; index < values.length; index += step) {
      spots.add(FlSpot((index - lastIndex) / samplingRate, values[index]));
    }
    if ((values.length - 1) % step != 0) {
      spots.add(FlSpot(0, values.last));
    }
    return spots;
  }
}

class _QualityBadge extends StatelessWidget {
  final EegChannelQuality quality;

  const _QualityBadge({required this.quality});

  @override
  Widget build(BuildContext context) {
    final label = quality.clipping
        ? 'CLIP'
        : quality.flat
        ? 'FLAT'
        : 'HIGH';
    return Tooltip(
      message: quality.clipping
          ? 'Kanał osiąga zakres pomiarowy'
          : quality.flat
          ? 'Kanał nie zmienia wartości'
          : 'Wysoka amplituda sygnału',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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
