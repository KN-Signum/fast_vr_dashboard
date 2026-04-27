import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/eeg_provider.dart';

const double _kPanelWidth = 280;

// Line colours per band
const Map<String, Color> _kBandColors = {
  'alpha': Color(0xFF4C8BF5), // blue
  'beta': Color(0xFF34A853), // green
  'theta': Color(0xFFFF9800), // orange
};

class EegPanel extends StatelessWidget {
  const EegPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kPanelWidth,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                _BandPowerChart(),
                SizedBox(height: 16),
                _ErdBarChart(),
                SizedBox(height: 16),
                _FocusIndexBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.blue.shade700),
      child: const Row(
        children: [
          Icon(Icons.psychology, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text(
            'EEG SIGNALS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Band Power Line Chart ────────────────────────────────────────────────────

class _BandPowerChart extends StatelessWidget {
  const _BandPowerChart();

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final channels = eeg.latest?.channels ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('EEG Raw Signal (µV) - All Channels'),
        const SizedBox(height: 8),
        if (channels.isEmpty)
          _placeholder('Waiting for EEG data...')
        else
          ...channels
              .map(
                (channel) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ChannelSignalChart(channel: channel),
                ),
              )
              .toList(),
      ],
    );
  }
}

class _ChannelSignalChart extends StatelessWidget {
  final String channel;

  const _ChannelSignalChart({required this.channel});

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final rawSignal = eeg.latest?.rawSignal[channel] ?? [];

    if (rawSignal.isEmpty) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            '$channel - No data',
            style: const TextStyle(fontSize: 9, color: Colors.black38),
          ),
        ),
      );
    }

    final spots = rawSignal
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          channel,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 50,
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: Colors.blue.shade500,
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 7, color: Colors.black38),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
              ),
              lineTouchData: const LineTouchData(enabled: false),
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }
}

// ─── ERD% Bar Chart ───────────────────────────────────────────────────────────

class _ErdBarChart extends StatelessWidget {
  const _ErdBarChart();

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final channels = eeg.getChannels();
    final alphaErd = eeg.latestErd('alpha');
    final betaErd = eeg.latestErd('beta');

    // Show placeholder if no ERD data available
    if (alphaErd.isEmpty && betaErd.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('ERD% per Channel (alpha · beta)'),
          const SizedBox(height: 8),
          _placeholder('Waiting for ERD data...'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('ERD% per Channel (alpha · beta)'),
        const SizedBox(height: 8),
        ...channels.asMap().entries.map((entry) {
          final i = entry.key;
          final ch = entry.value;
          final a = i < alphaErd.length ? alphaErd[i] : 0.0;
          final b = i < betaErd.length ? betaErd[i] : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _ErdChannelRow(channel: ch, alpha: a, beta: b),
          );
        }),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              '−  desync',
              style: TextStyle(fontSize: 8, color: Colors.black38),
            ),
            Text(
              '+ sync',
              style: TextStyle(fontSize: 8, color: Colors.black38),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErdChannelRow extends StatelessWidget {
  final String channel;
  final double alpha;
  final double beta;

  const _ErdChannelRow({
    required this.channel,
    required this.alpha,
    required this.beta,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            channel,
            style: const TextStyle(fontSize: 9, color: Colors.black54),
          ),
        ),
        Expanded(child: _erdBar(alpha, _kBandColors['alpha']!)),
        const SizedBox(width: 2),
        Expanded(child: _erdBar(beta, _kBandColors['beta']!)),
      ],
    );
  }

  Widget _erdBar(double value, Color color) {
    // Map ERD% (-60..+60) to 0..1 for bar, centered at 0.5
    const range = 60.0;
    final clamped = value.clamp(-range, range);
    final normalizedWidth = (clamped.abs() / range);
    final isNegative = value < 0;

    return LayoutBuilder(
      builder: (_, constraints) {
        final maxW = constraints.maxWidth;
        return Stack(
          children: [
            // Background
            Container(height: 8, color: Colors.grey.shade200),
            // Bar — grows from center
            Positioned(
              left: isNegative
                  ? maxW / 2 - normalizedWidth * (maxW / 2)
                  : maxW / 2,
              child: Container(
                width: normalizedWidth * (maxW / 2),
                height: 8,
                color: color.withValues(alpha: 0.7),
              ),
            ),
            // Center line
            Positioned(
              left: maxW / 2,
              child: Container(
                width: 1,
                height: 8,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Focus Index ──────────────────────────────────────────────────────────────

class _FocusIndexBar extends StatelessWidget {
  const _FocusIndexBar();

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final focus = eeg.latest?.focusIndex ?? 0.0;

    // Show placeholder if data indicates feature not available
    if (eeg.latest?.focusIndex == null || eeg.latest?.focusIndex == 0.0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Focus Index'),
          const SizedBox(height: 6),
          _placeholder('Not available'),
        ],
      );
    }

    final color = Color.lerp(Colors.green, Colors.red, focus)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Focus Index'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: focus,
            minHeight: 14,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Focused',
              style: TextStyle(fontSize: 8, color: Colors.black38),
            ),
            Text(
              focus.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const Text(
              'Relaxed',
              style: TextStyle(fontSize: 8, color: Colors.black38),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _sectionLabel(String text) => Text(
  text,
  style: TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade600,
    letterSpacing: 0.3,
  ),
);

Widget _placeholder(String msg) => Center(
  child: Text(msg, style: const TextStyle(fontSize: 11, color: Colors.black38)),
);
