import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_style.dart';

class EyeTrackingSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? analysis;

  const EyeTrackingSummaryCard({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final data = analysis;
    final validPoints = _integer(data?['valid_points']);
    final totalRecords = _integer(data?['total_records']);

    return SectionPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rozkład spojrzenia',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (data == null || validPoints == 0)
            const Text(
              'Brak poprawnych punktów spojrzenia z projekcją na ekran.',
              style: TextStyle(color: AppColors.muted),
            )
          else ...[
            Text(
              'Poprawne punkty: $validPoints / $totalRecords '
              '(${_percent(data['valid_percent'])})',
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final heatmap = _heatmap(data['heatmap_percent']);
                final details = _DirectionDetails(analysis: data);
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      _Heatmap(values: heatmap),
                      const SizedBox(height: 18),
                      details,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _Heatmap(values: heatmap)),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: details),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Opisowy rozkład zapisanych punktów spojrzenia; bez '
              'interpretacji diagnostycznej.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final List<List<double>> values;

  const _Heatmap({required this.values});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('GÓRA', style: _axisStyle),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 36,
              child: Text(
                'LEWO',
                textAlign: TextAlign.center,
                style: _axisStyle,
              ),
            ),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.5,
                child: CustomPaint(
                  key: const ValueKey('eye-tracking-heatmap'),
                  painter: _HeatmapPainter(values),
                ),
              ),
            ),
            const SizedBox(
              width: 42,
              child: Text(
                'PRAWO',
                textAlign: TextAlign.center,
                style: _axisStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('DÓŁ', style: _axisStyle),
        const SizedBox(height: 6),
        const Text(
          'Ciemniejszy kolor oznacza większy udział punktów.',
          style: TextStyle(color: AppColors.muted, fontSize: 10),
        ),
      ],
    );
  }
}

class _DirectionDetails extends StatelessWidget {
  final Map<String, dynamic> analysis;

  const _DirectionDetails({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final horizontal = _map(analysis['horizontal']);
    final vertical = _map(analysis['vertical']);
    final regions = _map(analysis['regions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PercentageRow(
          title: 'Poziomo',
          entries: [
            ('Lewo', horizontal['left']),
            ('Środek', horizontal['center']),
            ('Prawo', horizontal['right']),
          ],
        ),
        const SizedBox(height: 12),
        _PercentageRow(
          title: 'Pionowo',
          entries: [
            ('Góra', vertical['top']),
            ('Środek', vertical['middle']),
            ('Dół', vertical['bottom']),
          ],
        ),
        const SizedBox(height: 16),
        _RegionTable(regions: regions),
      ],
    );
  }
}

class _PercentageRow extends StatelessWidget {
  final String title;
  final List<(String, dynamic)> entries;

  const _PercentageRow({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: entries
              .map(
                (entry) => Expanded(
                  child: Column(
                    children: [
                      Text(
                        _percent(entry.$2),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        entry.$1,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _RegionTable extends StatelessWidget {
  final Map<String, dynamic> regions;

  const _RegionTable({required this.regions});

  @override
  Widget build(BuildContext context) {
    const columns = ['Lewo', 'Środek', 'Prawo'];
    const rows = [('top', 'Góra'), ('middle', 'Środek'), ('bottom', 'Dół')];
    return Table(
      border: TableBorder.all(color: AppColors.border),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.primary),
          children: [const SizedBox(height: 28), ...columns.map(_headerCell)],
        ),
        ...rows.map(
          (row) => TableRow(
            children: [
              _headerCell(row.$2),
              _valueCell(regions['${row.$1}_left']),
              _valueCell(regions['${row.$1}_center']),
              _valueCell(regions['${row.$1}_right']),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _headerCell(String value) => Container(
    height: 28,
    alignment: Alignment.center,
    color: AppColors.primary,
    child: Text(
      value,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static Widget _valueCell(dynamic value) => SizedBox(
    height: 28,
    child: Center(
      child: Text(_percent(value), style: const TextStyle(fontSize: 11)),
    ),
  );
}

class _HeatmapPainter extends CustomPainter {
  final List<List<double>> values;

  const _HeatmapPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final rows = values.length;
    final columns = values.map((row) => row.length).fold(0, math.max);
    if (columns == 0) return;
    final maximum = values
        .expand((row) => row)
        .fold<double>(0, (current, value) => math.max(current, value));
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    final paint = Paint();
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final value = column < values[row].length ? values[row][column] : 0.0;
        final ratio = maximum <= 0 ? 0.0 : (value / maximum).clamp(0.0, 1.0);
        paint.color = Color.lerp(
          AppColors.surfaceAlt,
          AppColors.primary,
          value > 0 ? 0.08 + ratio * 0.92 : 0,
        )!;
        final rect = Rect.fromLTWH(
          column * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, border);
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.values != values;
}

const _axisStyle = TextStyle(
  color: AppColors.muted,
  fontSize: 10,
  fontWeight: FontWeight.w700,
);

int _integer(dynamic value) => value is num ? value.toInt() : 0;

String _percent(dynamic value) {
  final number = value is num ? value.toDouble() : 0.0;
  return '${number.toStringAsFixed(1)}%';
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<List<double>> _heatmap(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<List>()
      .map(
        (row) => row
            .map((cell) => cell is num ? cell.toDouble() : 0.0)
            .toList(growable: false),
      )
      .toList(growable: false);
}
