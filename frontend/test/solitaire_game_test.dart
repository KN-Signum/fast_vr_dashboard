import 'package:card_game/card_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/features/solitaire/solitaire_game.dart';
import 'package:vr_fast_dashboard/features/solitaire/solitaire_overlay.dart';

void main() {
  test('new game deals every card exactly once', () {
    final state = SolitaireState.newGame();
    final dealtCards = <SuitedCard>[
      ...state.stock,
      ...state.waste,
      ...state.hiddenCards.expand((cards) => cards),
      ...state.revealedCards.expand((cards) => cards),
      ...state.foundations.values.expand((cards) => cards),
    ];

    expect(dealtCards, hasLength(52));
    expect(dealtCards.toSet(), hasLength(52));
    expect(state.hiddenCards.map((cards) => cards.length), [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
    ]);
    expect(state.revealedCards.every((cards) => cards.length == 1), isTrue);
  });

  test('drawing the whole stock and recycling it preserves its order', () {
    var state = SolitaireState.newGame();
    final originalStock = List<SuitedCard>.of(state.stock);

    while (state.stock.isNotEmpty) {
      state = state.drawOrRecycle();
    }
    expect(state.waste, originalStock.reversed);

    state = state.drawOrRecycle();
    expect(state.stock, originalStock);
    expect(state.waste, isEmpty);
  });

  test('only an ace can start a foundation', () {
    final state = SolitaireState(
      hiddenCards: List.generate(7, (_) => <SuitedCard>[]),
      revealedCards: List.generate(7, (_) => <SuitedCard>[]),
      stock: const [],
      waste: const [],
      foundations: {for (final suit in CardSuit.values) suit: <SuitedCard>[]},
    );
    final ace = SuitedCard(suit: CardSuit.hearts, value: AceSuitedCardValue());
    final two = SuitedCard(
      suit: CardSuit.hearts,
      value: NumberSuitedCardValue(value: 2),
    );

    expect(state.canPlaceOnFoundation(ace, CardSuit.hearts), isTrue);
    expect(state.canPlaceOnFoundation(two, CardSuit.hearts), isFalse);
    expect(state.canPlaceOnFoundation(ace, CardSuit.spades), isFalse);
  });

  testWidgets('solitaire overlay exposes reset and close controls', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: SolitaireOverlay(visible: true, onClose: () => closed = true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pasjans'), findsOneWidget);
    expect(find.byKey(const ValueKey('solitaire-game')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('solitaire-new-game')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('solitaire-close')));
    expect(closed, isTrue);
  });
}
