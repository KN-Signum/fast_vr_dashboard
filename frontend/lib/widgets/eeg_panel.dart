import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../theme/app_style.dart';

const double _kPanelWidth = 320;

const Map<String, Color> _kBandColors = {
  'theta': Color(0xFFFF9800),
  'alpha': Color(0xFF4C8BF5),
  'beta': Color(0xFF34A853),
};

const List<String> _kMotorChannels = ['C3', 'C4'];
const List<String> _kPosteriorChannels = ['P3', 'P4', 'O1', 'O2'];

enum _ChannelScope { all, motor, posterior, single }

enum _SignalQuality { bad, medium, good }

class EegPanel extends StatefulWidget {
  const EegPanel({super.key});

  @override
  State<EegPanel> createState() => _EegPanelState();
}

class _EegPanelState extends State<EegPanel> {
  _ChannelScope _scope = _ChannelScope.all;
  String? _singleChannel;
  bool _rawPreviewExpanded = false;

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<EegProvider>();
    final latest = eeg.latest;
    final availableChannels = eeg.getChannels();
    final selectedChannels = _selectedChannels(availableChannels);
    final eegOn = latest != null;
    final quality = _signalQuality(latest);

    return Container(
      width: _kPanelWidth,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            eegOn: eegOn,
            samplingRate: latest?.samplingRate ?? 250,
            channelCount: availableChannels.length,
            quality: quality,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _controlCard(availableChannels),
                const SizedBox(height: 12),
                _AvgSignalCard(
                  snapshots: eeg.snapshots,
                  channels: selectedChannels,
                ),
                const SizedBox(height: 12),
                _BandPowerCard(
                  snapshots: eeg.snapshots,
                  channels: selectedChannels,
                ),
                const SizedBox(height: 12),
                _ErdCard(latest: latest, channels: availableChannels),
                const SizedBox(height: 12),
                _rawPreviewCard(latest, selectedChannels),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlCard(List<String> channels) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Channel group'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _scopeChip('All', _ChannelScope.all),
              _scopeChip('Motor', _ChannelScope.motor),
              _scopeChip('Posterior', _ChannelScope.posterior),
              _scopeChip('Single', _ChannelScope.single),
            ],
          ),
          if (_scope == _ChannelScope.single) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Channel',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isDense: true,
                        value:
                            _singleChannel ??
                            (channels.isNotEmpty ? channels.first : null),
                        items: channels
                            .map(
                              (channel) => DropdownMenuItem<String>(
                                value: channel,
                                child: Text(
                                  channel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _singleChannel = value);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeChip(String label, _ChannelScope scope) {
    final selected = _scope == scope;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _scope = scope;
          if (scope != _ChannelScope.single) {
            _rawPreviewExpanded = false;
          }
        });
      },
      selectedColor: Colors.blue.shade100,
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(
        color: selected ? Colors.blue.shade300 : Colors.grey.shade300,
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _rawPreviewCard(EegSnapshot? latest, List<String> selectedChannels) {
    return _CardShell(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        childrenPadding: const EdgeInsets.only(top: 8),
        initiallyExpanded: _rawPreviewExpanded,
        onExpansionChanged: (value) =>
            setState(() => _rawPreviewExpanded = value),
        title: Text(
          'Raw Channels',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        subtitle: Text(
          'Collapsed by default',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
        children: [
          if (latest == null)
            _placeholder('Waiting for EEG data...')
          else
            ...selectedChannels.map(
              (channel) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RawChannelChart(channel: channel, snapshot: latest),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _selectedChannels(List<String> available) {
    final channels = available.isNotEmpty ? available : kEegChannels;

    switch (_scope) {
      case _ChannelScope.motor:
        return channels.where(_kMotorChannels.contains).toList();
      case _ChannelScope.posterior:
        return channels.where(_kPosteriorChannels.contains).toList();
      case _ChannelScope.single:
        final selected = _singleChannel ?? channels.first;
        return channels.contains(selected) ? [selected] : [channels.first];
      case _ChannelScope.all:
        return channels;
    }
  }

  _SignalQuality _signalQuality(EegSnapshot? snapshot) {
    if (snapshot == null) return _SignalQuality.bad;

    final values = snapshot.rawSignal.values
        .expand((series) => series.take(math.min(64, series.length)))
        .map((value) => value.abs())
        .toList(growable: false);

    if (values.isEmpty) return _SignalQuality.bad;

    final meanAbs = values.reduce((a, b) => a + b) / values.length;
    if (meanAbs < 1.0 || meanAbs > 2000.0) return _SignalQuality.bad;
    if (meanAbs < 4.0 || meanAbs > 700.0) return _SignalQuality.medium;
    return _SignalQuality.good;
  }
}

class _Header extends StatelessWidget {
  final bool eegOn;
  final int samplingRate;
  final int channelCount;
  final _SignalQuality quality;

  const _Header({
    required this.eegOn,
    required this.samplingRate,
    required this.channelCount,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final qualityColor = switch (quality) {
      _SignalQuality.good => Colors.green,
      _SignalQuality.medium => Colors.orange,
      _SignalQuality.bad => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(color: AppColors.primaryDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill('EEG: ${eegOn ? 'ON' : 'OFF'}'),
              _pill('$samplingRate Hz'),
              _pill('$channelCount ch'),
              _pill(
                'Signal: ${quality.name.toUpperCase()}',
                backgroundColor: qualityColor.withValues(alpha: 0.18),
                borderColor: qualityColor.withValues(alpha: 0.35),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(
    String text, {
    Color backgroundColor = const Color(0x22FFFFFF),
    Color borderColor = const Color(0x33FFFFFF),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AvgSignalCard extends StatelessWidget {
  final List<EegSnapshot> snapshots;
  final List<String> channels;

  const _AvgSignalCard({required this.snapshots, required this.channels});

  @override
  Widget build(BuildContext context) {
    final series = _averageSignalSeries();

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartHeader(
            'Avg EEG Signal',
            subtitle: 'Live window ~1-5 s',
            unit: 'µV',
          ),
          const SizedBox(height: 8),
          if (series.isEmpty)
            _placeholder('Waiting for EEG data...')
          else
            SizedBox(
              height: 150,
              child: LineChart(
                _singleLineChartData(series, Colors.blue.shade600),
                duration: Duration.zero,
              ),
            ),
        ],
      ),
    );
  }

  List<double> _averageSignalSeries() {
    final relevant = snapshots.length > 5
        ? snapshots.sublist(snapshots.length - 5)
        : snapshots;
    final points = <double>[];

    for (final snapshot in relevant) {
      final waveforms = <List<double>>[];
      for (final channel in channels) {
        final samples = snapshot.rawSignal[channel];
        if (samples != null && samples.isNotEmpty) {
          waveforms.add(samples);
        }
      }

      if (waveforms.isEmpty) continue;

      final minLength = waveforms
          .map((series) => series.length)
          .reduce(math.min);
      for (var i = 0; i < minLength; i++) {
        double sum = 0.0;
        for (final series in waveforms) {
          sum += series[i];
        }
        points.add(sum / waveforms.length);
      }
    }

    return points;
  }
}

class _BandPowerCard extends StatelessWidget {
  final List<EegSnapshot> snapshots;
  final List<String> channels;

  const _BandPowerCard({required this.snapshots, required this.channels});

  @override
  Widget build(BuildContext context) {
    final theta = _bandSeries('theta');
    final alpha = _bandSeries('alpha');
    final beta = _bandSeries('beta');

    final hasData = theta.isNotEmpty || alpha.isNotEmpty || beta.isNotEmpty;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartHeader(
            'Band Power Over Time',
            subtitle: 'Theta, Alpha / Mu, Beta',
          ),
          const SizedBox(height: 8),
          if (!hasData)
            _placeholder('Waiting for band power data...')
          else ...[
            _LegendRow(
              items: [
                _LegendItem(label: 'Theta', color: _kBandColors['theta']!),
                _LegendItem(label: 'Alpha / Mu', color: _kBandColors['alpha']!),
                _LegendItem(label: 'Beta', color: _kBandColors['beta']!),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: LineChart(
                _multiLineChartData({
                  'theta': theta,
                  'alpha': alpha,
                  'beta': beta,
                }),
                duration: Duration.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<double> _bandSeries(String band) {
    final relevant = snapshots.length > 50
        ? snapshots.sublist(snapshots.length - 50)
        : snapshots;

    return relevant
        .map((snapshot) {
          final values = snapshot.bandPower[band];
          if (values == null || values.isEmpty) return 0.0;

          final selected = <double>[];
          for (final channel in channels) {
            final index = snapshot.channels.indexOf(channel);
            if (index >= 0 && index < values.length) {
              selected.add(values[index]);
            }
          }

          final source = selected.isEmpty ? values : selected;
          return source.reduce((a, b) => a + b) / source.length;
        })
        .toList(growable: false);
  }
}

class _ErdCard extends StatelessWidget {
  final EegSnapshot? latest;
  final List<String> channels;

  const _ErdCard({required this.latest, required this.channels});

  @override
  Widget build(BuildContext context) {
    final alpha = latest == null
        ? const <double>[]
        : (latest!.erd['alpha'] ?? const <double>[]);
    final beta = latest == null
        ? const <double>[]
        : (latest!.erd['beta'] ?? const <double>[]);
    final visibleChannels = latest?.channels.isNotEmpty == true
        ? latest!.channels
        : channels;
    final hasData = alpha.isNotEmpty || beta.isNotEmpty;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartHeader('ERD / ERS per Channel', subtitle: 'Alpha / Mu + Beta'),
          const SizedBox(height: 8),
          if (!hasData)
            _placeholder('Waiting for ERD data...')
          else ...[
            _LegendRow(
              items: [
                _LegendItem(label: 'Alpha / Mu', color: _kBandColors['alpha']!),
                _LegendItem(label: 'Beta', color: _kBandColors['beta']!),
              ],
            ),
            const SizedBox(height: 8),
            ...visibleChannels.asMap().entries.map((entry) {
              final index = entry.key;
              final channel = entry.value;
              final alphaValue = index < alpha.length ? alpha[index] : 0.0;
              final betaValue = index < beta.length ? beta[index] : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _ErdChannelRow(
                  channel: channel,
                  alpha: alphaValue,
                  beta: betaValue,
                ),
              );
            }),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ERD',
                  style: TextStyle(fontSize: 8, color: Colors.black38),
                ),
                Text('0', style: TextStyle(fontSize: 8, color: Colors.black38)),
                Text(
                  'ERS',
                  style: TextStyle(fontSize: 8, color: Colors.black38),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RawChannelChart extends StatelessWidget {
  final String channel;
  final EegSnapshot snapshot;

  const _RawChannelChart({required this.channel, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final rawSignal = snapshot.rawSignal[channel] ?? const <double>[];

    if (rawSignal.isEmpty) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            '$channel - No data',
            style: const TextStyle(fontSize: 9, color: Colors.black38),
          ),
        ),
      );
    }

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
        const SizedBox(height: 4),
        SizedBox(
          height: 54,
          child: LineChart(
            _singleLineChartData(rawSignal, Colors.blue.shade500),
            duration: Duration.zero,
          ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            channel,
            style: const TextStyle(fontSize: 9, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ErdValueBar(value: alpha, color: _kBandColors['alpha']!),
              const SizedBox(height: 4),
              _ErdValueBar(value: beta, color: _kBandColors['beta']!),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            '${_formatSigned(alpha)} / ${_formatSigned(beta)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 9, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

class _ErdValueBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ErdValueBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    const range = 60.0;
    final clamped = value.clamp(-range, range);
    final normalizedWidth = clamped.abs() / range;
    final isNegative = value < 0;

    return LayoutBuilder(
      builder: (_, constraints) {
        final maxWidth = constraints.maxWidth;
        return Stack(
          children: [
            Container(height: 8, color: Colors.grey.shade200),
            Positioned(
              left: maxWidth / 2,
              child: Container(
                width: 1,
                height: 8,
                color: Colors.grey.shade400,
              ),
            ),
            Positioned(
              left: isNegative
                  ? maxWidth / 2 - normalizedWidth * (maxWidth / 2)
                  : maxWidth / 2,
              child: Container(
                width: normalizedWidth * (maxWidth / 2),
                height: 8,
                color: color.withValues(alpha: 0.75),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _LegendRow extends StatelessWidget {
  final List<_LegendItem> items;

  const _LegendRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.label,
                  style: const TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ],
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;

  const _LegendItem({required this.label, required this.color});
}

Widget _chartHeader(String title, {String? subtitle, String? unit}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
      ),
      if (unit != null)
        Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ],
  );
}

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
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      msg,
      style: const TextStyle(fontSize: 11, color: Colors.black38),
    ),
  ),
);

String _formatSigned(double value) {
  final prefix = value >= 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(0)}%';
}

LineChartData _singleLineChartData(List<double> values, Color color) {
  final spots = values
      .asMap()
      .entries
      .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
      .toList(growable: false);
  final yValues = values.isEmpty ? const [0.0] : values;
  final minY = yValues.reduce(math.min);
  final maxY = yValues.reduce(math.max);
  final padding = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY) * 0.15;

  return LineChartData(
    minY: minY - padding,
    maxY: maxY + padding,
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
          reservedSize: 34,
          getTitlesWidget: (value, _) => Text(
            value.toStringAsFixed(0),
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
    lineBarsData: [
      LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: 1.25,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ),
    ],
    lineTouchData: const LineTouchData(enabled: false),
  );
}

LineChartData _multiLineChartData(Map<String, List<double>> seriesByBand) {
  final bars = <LineChartBarData>[];
  double? minY;
  double? maxY;

  for (final entry in seriesByBand.entries) {
    final values = entry.value;
    if (values.isEmpty) continue;

    final bandMin = values.reduce(math.min);
    final bandMax = values.reduce(math.max);
    minY = minY == null ? bandMin : math.min(minY, bandMin);
    maxY = maxY == null ? bandMax : math.max(maxY, bandMax);

    bars.add(
      LineChartBarData(
        spots: values
            .asMap()
            .entries
            .map((item) => FlSpot(item.key.toDouble(), item.value))
            .toList(growable: false),
        isCurved: false,
        color: _kBandColors[entry.key] ?? Colors.blue,
        barWidth: 1.25,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ),
    );
  }

  if (minY == null || maxY == null) {
    minY = 0.0;
    maxY = 1.0;
  }

  final padding = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY) * 0.15;

  return LineChartData(
    minY: minY - padding,
    maxY: maxY + padding,
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
          reservedSize: 34,
          getTitlesWidget: (value, _) => Text(
            value.toStringAsFixed(0),
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
    lineBarsData: bars,
    lineTouchData: const LineTouchData(enabled: false),
  );
}
