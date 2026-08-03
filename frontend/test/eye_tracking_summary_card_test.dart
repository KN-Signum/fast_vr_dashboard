import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/widgets/eye_tracking_summary_card.dart';

void main() {
  testWidgets('shows gaze heatmap and directional percentages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: EyeTrackingSummaryCard(
              analysis: {
                'total_records': 100,
                'valid_points': 80,
                'valid_percent': 80.0,
                'heatmap_percent': [
                  [10.0, 20.0],
                  [30.0, 40.0],
                ],
                'horizontal': {'left': 40.0, 'center': 20.0, 'right': 40.0},
                'vertical': {'top': 30.0, 'middle': 40.0, 'bottom': 30.0},
                'regions': {
                  'top_left': 10.0,
                  'top_center': 10.0,
                  'top_right': 10.0,
                  'middle_left': 20.0,
                  'middle_center': 10.0,
                  'middle_right': 10.0,
                  'bottom_left': 10.0,
                  'bottom_center': 0.0,
                  'bottom_right': 20.0,
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Rozkład spojrzenia'), findsOneWidget);
    expect(find.text('Poprawne punkty: 80 / 100 (80.0%)'), findsOneWidget);
    expect(find.byKey(const ValueKey('eye-tracking-heatmap')), findsOneWidget);
    expect(find.text('Poziomo'), findsOneWidget);
    expect(find.text('Pionowo'), findsOneWidget);
  });

  testWidgets('shows unavailable state without projected gaze', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EyeTrackingSummaryCard(
            analysis: {'total_records': 20, 'valid_points': 0},
          ),
        ),
      ),
    );

    expect(
      find.text('Brak poprawnych punktów spojrzenia z projekcją na ekran.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('eye-tracking-heatmap')), findsNothing);
  });
}
