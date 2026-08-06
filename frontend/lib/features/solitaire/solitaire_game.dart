import 'package:card_game/card_game.dart';
import 'package:flutter/material.dart';

const _stockGroup = 'stock';
const _wasteGroup = 'waste';

class SolitaireState {
  final List<List<SuitedCard>> hiddenCards;
  final List<List<SuitedCard>> revealedCards;
  final List<SuitedCard> stock;
  final List<SuitedCard> waste;
  final Map<CardSuit, List<SuitedCard>> foundations;

  const SolitaireState({
    required this.hiddenCards,
    required this.revealedCards,
    required this.stock,
    required this.waste,
    required this.foundations,
  });

  factory SolitaireState.newGame() {
    var deck = List<SuitedCard>.of(SuitedCard.deck)..shuffle();
    final hiddenCards = <List<SuitedCard>>[];
    final revealedCards = <List<SuitedCard>>[];

    for (var column = 0; column < 7; column++) {
      hiddenCards.add(deck.take(column).toList());
      deck = deck.skip(column).toList();
      revealedCards.add([deck.first]);
      deck = deck.skip(1).toList();
    }

    return SolitaireState(
      hiddenCards: hiddenCards,
      revealedCards: revealedCards,
      stock: deck,
      waste: const [],
      foundations: {for (final suit in CardSuit.values) suit: const []},
    );
  }

  bool get isWon =>
      foundations.values.fold<int>(0, (sum, cards) => sum + cards.length) == 52;

  int _valueOf(SuitedCard card) =>
      SuitedCardValueMapper.aceAsLowest.getValue(card);

  bool canPlaceOnFoundation(SuitedCard card, CardSuit suit) {
    if (card.suit != suit) return false;
    final cards = foundations[suit]!;
    return cards.isEmpty
        ? card.value is AceSuitedCardValue
        : _valueOf(cards.last) + 1 == _valueOf(card);
  }

  bool canPlaceOnTableau(List<SuitedCard> cards, int column) {
    if (cards.isEmpty) return false;
    final destination = revealedCards[column];
    final movingCard = cards.first;

    return destination.isEmpty
        ? movingCard.value is KingSuitedCardValue
        : _valueOf(movingCard) + 1 == _valueOf(destination.last) &&
              movingCard.suit.color != destination.last.suit.color;
  }

  SolitaireState drawOrRecycle() {
    if (stock.isEmpty) {
      if (waste.isEmpty) return this;
      return copyWith(stock: waste.reversed.toList(), waste: const []);
    }

    return copyWith(
      stock: stock.sublist(0, stock.length - 1),
      waste: [...waste, stock.last],
    );
  }

  SolitaireState autoMoveFromTableau(int column, int cardIndex) {
    final cards = revealedCards[column].sublist(cardIndex);
    if (cards.length == 1 &&
        canPlaceOnFoundation(cards.first, cards.first.suit)) {
      return moveToFoundation(cards, column, cards.first.suit);
    }

    for (var destination = 0; destination < 7; destination++) {
      if (destination != column && canPlaceOnTableau(cards, destination)) {
        return moveToTableau(cards, column, destination);
      }
    }
    return this;
  }

  SolitaireState autoMoveFromWaste() {
    if (waste.isEmpty) return this;
    final card = waste.last;
    if (canPlaceOnFoundation(card, card.suit)) {
      return moveToFoundation([card], _wasteGroup, card.suit);
    }

    for (var destination = 0; destination < 7; destination++) {
      if (canPlaceOnTableau([card], destination)) {
        return moveToTableau([card], _wasteGroup, destination);
      }
    }
    return this;
  }

  SolitaireState autoMoveFromFoundation(CardSuit suit) {
    final cards = foundations[suit]!;
    if (cards.isEmpty) return this;

    for (var destination = 0; destination < 7; destination++) {
      if (canPlaceOnTableau([cards.last], destination)) {
        return moveToTableau([cards.last], suit, destination);
      }
    }
    return this;
  }

  SolitaireState moveToTableau(
    List<SuitedCard> cards,
    Object source,
    int destination,
  ) {
    if (!canPlaceOnTableau(cards, destination)) return this;

    final newRevealed = _copyColumns(revealedCards);
    final newHidden = _copyColumns(hiddenCards);
    final newFoundations = _copyFoundations();
    var newWaste = List<SuitedCard>.of(waste);

    if (source is int) {
      newRevealed[source].removeRange(
        newRevealed[source].length - cards.length,
        newRevealed[source].length,
      );
      _revealNextCard(source, newHidden, newRevealed);
    } else if (source == _wasteGroup) {
      newWaste.removeLast();
    } else if (source is CardSuit) {
      newFoundations[source]!.removeLast();
    } else {
      return this;
    }

    newRevealed[destination].addAll(cards);
    return copyWith(
      hiddenCards: newHidden,
      revealedCards: newRevealed,
      waste: newWaste,
      foundations: newFoundations,
    );
  }

  SolitaireState moveToFoundation(
    List<SuitedCard> cards,
    Object source,
    CardSuit destination,
  ) {
    if (cards.length != 1 || !canPlaceOnFoundation(cards.single, destination)) {
      return this;
    }

    final newRevealed = _copyColumns(revealedCards);
    final newHidden = _copyColumns(hiddenCards);
    final newFoundations = _copyFoundations();
    var newWaste = List<SuitedCard>.of(waste);

    if (source is int) {
      newRevealed[source].removeLast();
      _revealNextCard(source, newHidden, newRevealed);
    } else if (source == _wasteGroup) {
      newWaste.removeLast();
    } else {
      return this;
    }

    newFoundations[destination]!.add(cards.single);
    return copyWith(
      hiddenCards: newHidden,
      revealedCards: newRevealed,
      waste: newWaste,
      foundations: newFoundations,
    );
  }

  void _revealNextCard(
    int column,
    List<List<SuitedCard>> hidden,
    List<List<SuitedCard>> revealed,
  ) {
    if (revealed[column].isEmpty && hidden[column].isNotEmpty) {
      revealed[column].add(hidden[column].removeLast());
    }
  }

  List<List<SuitedCard>> _copyColumns(List<List<SuitedCard>> columns) =>
      columns.map(List<SuitedCard>.of).toList();

  Map<CardSuit, List<SuitedCard>> _copyFoundations() => {
    for (final entry in foundations.entries)
      entry.key: List<SuitedCard>.of(entry.value),
  };

  SolitaireState copyWith({
    List<List<SuitedCard>>? hiddenCards,
    List<List<SuitedCard>>? revealedCards,
    List<SuitedCard>? stock,
    List<SuitedCard>? waste,
    Map<CardSuit, List<SuitedCard>>? foundations,
  }) {
    return SolitaireState(
      hiddenCards: hiddenCards ?? this.hiddenCards,
      revealedCards: revealedCards ?? this.revealedCards,
      stock: stock ?? this.stock,
      waste: waste ?? this.waste,
      foundations: foundations ?? this.foundations,
    );
  }
}

class SolitaireGame extends StatefulWidget {
  final int gameNumber;

  const SolitaireGame({super.key, required this.gameNumber});

  @override
  State<SolitaireGame> createState() => _SolitaireGameState();
}

class _SolitaireGameState extends State<SolitaireGame> {
  late SolitaireState _state;

  @override
  void initState() {
    super.initState();
    _state = SolitaireState.newGame();
  }

  @override
  void didUpdateWidget(covariant SolitaireGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameNumber != widget.gameNumber) {
      _state = SolitaireState.newGame();
    }
  }

  void _update(SolitaireState state) {
    if (!identical(state, _state)) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 18.0;
        const gap = 8.0;
        final widthForCards =
            constraints.maxWidth - (horizontalPadding * 2) - (gap * 6);
        final multiplier = (widthForCards / 7 / 64).clamp(0.62, 1.18);
        final cardWidth = 64 * multiplier;
        final cardHeight = 89 * multiplier;
        final tableauSpacing = (cardHeight * 0.28).clamp(15.0, 28.0);

        return Container(
          color: const Color(0xFF28745C),
          padding: const EdgeInsets.all(horizontalPadding),
          child: CardGame<SuitedCard, Object>(
            gameKey: widget.gameNumber,
            style: deckCardStyle<Object>(sizeMultiplier: multiplier),
            children: [
              Column(
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: Row(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _update(_state.drawOrRecycle()),
                          child: SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: CardDeck<SuitedCard, Object>.flipped(
                              value: _stockGroup,
                              values: _state.stock,
                            ),
                          ),
                        ),
                        const SizedBox(width: gap),
                        SizedBox(
                          width: cardWidth,
                          height: cardHeight,
                          child: CardDeck<SuitedCard, Object>(
                            value: _wasteGroup,
                            values: _state.waste,
                            canGrab: true,
                            onCardPressed: (_) =>
                                _update(_state.autoMoveFromWaste()),
                          ),
                        ),
                        const Spacer(),
                        for (final suit in CardSuit.values) ...[
                          SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: CardDeck<SuitedCard, Object>(
                              value: suit,
                              values: _state.foundations[suit]!,
                              onCardPressed: (_) =>
                                  _update(_state.autoMoveFromFoundation(suit)),
                              canMoveCardHere: (move) =>
                                  move.cardValues.length == 1 &&
                                  _state.canPlaceOnFoundation(
                                    move.cardValues.single,
                                    suit,
                                  ),
                              onCardMovedHere: (move) => _update(
                                _state.moveToFoundation(
                                  move.cardValues,
                                  move.fromGroupValue,
                                  suit,
                                ),
                              ),
                            ),
                          ),
                          if (suit != CardSuit.spades)
                            const SizedBox(width: gap),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (column) {
                        final hidden = _state.hiddenCards[column];
                        final revealed = _state.revealedCards[column];
                        return SizedBox(
                          width: cardWidth,
                          height: double.infinity,
                          child: CardColumn<SuitedCard, Object>(
                            value: column,
                            spacing: tableauSpacing,
                            values: [...hidden, ...revealed],
                            isCardFlipped: (_, card) => hidden.contains(card),
                            canCardBeGrabbed: (_, card) =>
                                revealed.contains(card),
                            onCardPressed: (card) {
                              final index = revealed.indexOf(card);
                              if (index >= 0) {
                                _update(
                                  _state.autoMoveFromTableau(column, index),
                                );
                              }
                            },
                            canMoveCardHere: (move) => _state.canPlaceOnTableau(
                              move.cardValues,
                              column,
                            ),
                            onCardMovedHere: (move) => _update(
                              _state.moveToTableau(
                                move.cardValues,
                                move.fromGroupValue,
                                column,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              if (_state.isWon)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Wygrana!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
