import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/widgets/bird_count_panel.dart';

void main() {
  testWidgets('shows generated and reported counts for both sides', (
    tester,
  ) async {
    var leftIncrements = 0;
    var rightIncrements = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 252,
            child: BirdCountPanel(
              visible: 8,
              visibleLeft: 4,
              visibleRight: 4,
              reportedLeft: 0,
              reportedRight: 2,
              onIncrementLeft: () => leftIncrements++,
              onDecrementLeft: () {},
              onIncrementRight: () => rightIncrements++,
              onDecrementRight: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Widoczne ptaki'), findsOneWidget);
    expect(find.text('Wygenerowane: 4'), findsNWidgets(2));
    expect(find.text('LEWA STRONA'), findsOneWidget);
    expect(find.text('PRAWA STRONA'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final button in find.byType(IconButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)), const Size(24, 24));
    }

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.tap(find.byIcon(Icons.add).last);
    expect(leftIncrements, 1);
    expect(rightIncrements, 1);
  });

  testWidgets('disables decrement when reported count is zero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirdCountPanel(
            visible: 3,
            visibleLeft: 1,
            visibleRight: 2,
            reportedLeft: 0,
            reportedRight: 1,
            onIncrementLeft: () {},
            onDecrementLeft: () {},
            onIncrementRight: () {},
            onDecrementRight: () {},
          ),
        ),
      ),
    );

    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons.first.onPressed, isNull);
    expect(buttons.elementAt(2).onPressed, isNotNull);
  });

  testWidgets('keeps the original compact view for the legacy payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirdCountPanel(
            visible: 8,
            reportedLeft: 0,
            reportedRight: 0,
            onIncrementLeft: () {},
            onDecrementLeft: () {},
            onIncrementRight: () {},
            onDecrementRight: () {},
          ),
        ),
      ),
    );

    expect(find.text('Widoczne ptaki'), findsOneWidget);
    expect(find.text('LEWA STRONA'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
