import 'package:flutter/material.dart';

import 'package:chess_trainer/core/chess/game.dart';

class ChessBoardView extends StatelessWidget {
  static const Color _lightWood = Color(0xFFE6C18A);
  static const Color _lightWoodGlow = Color(0xFFF7DCA8);
  static const Color _lightWoodGrain = Color(0xFFD5A66D);
  static const Color _darkWood = Color(0xFFAA6330);
  static const Color _darkWoodGlow = Color(0xFFC47B3E);
  static const Color _darkWoodGrain = Color(0xFF7E421F);
  static const Color _boardBorder = Color(0xFF5D321B);
  static const Color _lastMoveOverlay = Color(0x66F6D365);
  static const Color _selectedOverlay = Color(0x6650C7A7);
  static const Color _hoverOverlay = Color(0x5534D399);
  static const Color _legalMarker = Color(0x9934D399);

  final Game game;
  final bool flipped;
  final int? selectedSquare;
  final List<int> legalTargets;
  final int? lastMoveFrom;
  final int? lastMoveTo;
  final String? bestMoveFrom;
  final String? bestMoveTo;
  final String? checkedKingSquare;
  final bool isCheckmate;
  final Function(int) onSquareTap;
  final void Function(int fromSquare, int toSquare) onPieceDropped;

  const ChessBoardView({
    super.key,
    required this.game,
    required this.flipped,
    required this.selectedSquare,
    required this.legalTargets,
    required this.lastMoveFrom,
    required this.lastMoveTo,
    required this.bestMoveFrom,
    required this.bestMoveTo,
    required this.checkedKingSquare,
    required this.isCheckmate,
    required this.onSquareTap,
    required this.onPieceDropped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final feedbackSize = ((boardSize / 8) * 0.9).clamp(52.0, 96.0);
        final checkedKingIndex = checkedKingSquare == null
            ? null
            : squareNameToIndex(checkedKingSquare!);

        return AspectRatio(
          aspectRatio: 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _boardBorder,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: 64,
                  itemBuilder: (context, index) {
                    final visualRow = index ~/ 8;
                    final visualCol = index % 8;
                    final boardIndex = flipped ? 63 - index : index;

                    final piece = game.board[boardIndex];
                    final row = boardIndex ~/ 8;
                    final col = boardIndex % 8;
                    final rank = 8 - row;

                    final isDarkSquare = (row + col) % 2 == 1;
                    final isSelected = selectedSquare == boardIndex;
                    final isLegalTarget = legalTargets.contains(boardIndex);
                    final isLastMove =
                        boardIndex == lastMoveFrom || boardIndex == lastMoveTo;
                    final isCheckedKing = checkedKingIndex == boardIndex;
                    final canDragPiece = piece != null &&
                        piece.color == game.turn.displayName.toLowerCase();

                    final squareContent = _BoardSquare(
                      boardIndex: boardIndex,
                      file: col,
                      rank: rank,
                      visualRow: visualRow,
                      visualCol: visualCol,
                      isDarkSquare: isDarkSquare,
                      isSelected: isSelected,
                      isLegalTarget: isLegalTarget,
                      isLastMove: isLastMove,
                      isCheckedKing: isCheckedKing,
                      isCheckmate: isCheckmate,
                      piece: piece?.icon,
                    );

                    Widget child = squareContent;

                    if (canDragPiece) {
                      child = Draggable<int>(
                        data: boardIndex,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox.square(
                            dimension: feedbackSize.toDouble(),
                            child: Center(child: piece.icon),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: squareContent,
                        ),
                        child: squareContent,
                      );
                    }

                    return DragTarget<int>(
                      onWillAcceptWithDetails: (details) {
                        final fromSquare = details.data;
                        if (fromSquare == boardIndex) return false;
                        return true;
                      },
                      onAcceptWithDetails: (details) {
                        onPieceDropped(details.data, boardIndex);
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovering = candidateData.isNotEmpty;

                        return GestureDetector(
                          onTap: () => onSquareTap(boardIndex),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child,
                              if (isHovering)
                                const ColoredBox(color: _hoverOverlay),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                if (bestMoveFrom != null && bestMoveTo != null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _BestMoveArrowPainter(
                        fromSquare: bestMoveFrom!,
                        toSquare: bestMoveTo!,
                        flipped: flipped,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static BoxDecoration woodDecoration(bool isDarkSquare, int boardIndex) {
    final lightAmount = boardIndex.isEven ? 0.04 : 0.08;
    final darkAmount = boardIndex.isEven ? 0.06 : 0.02;

    if (isDarkSquare) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_darkWoodGlow, Colors.white, lightAmount)!,
            _darkWood,
            Color.lerp(_darkWoodGrain, Colors.black, darkAmount)!,
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
        border: Border.all(
          color: Colors.black.withAlpha(28),
          width: 0.35,
        ),
      );
    }

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(_lightWoodGlow, Colors.white, lightAmount)!,
          _lightWood,
          Color.lerp(_lightWoodGrain, Colors.black, darkAmount)!,
        ],
        stops: const [0.0, 0.52, 1.0],
      ),
      border: Border.all(
        color: Colors.black.withAlpha(18),
        width: 0.35,
      ),
    );
  }

  static Color coordinateColor(bool isDarkSquare) {
    return isDarkSquare ? const Color(0xFFEED7AF) : const Color(0xFF8B4C22);
  }

  static int? squareNameToIndex(String square) {
    if (square.length != 2) return null;

    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(square[1]);

    if (file < 0 || file > 7 || rank == null || rank < 1 || rank > 8) {
      return null;
    }

    return (8 - rank) * 8 + file;
  }

  static String indexToSquareName(int index) {
    if (index < 0 || index >= 64) return '';

    final file = index % 8;
    final rank = 8 - (index ~/ 8);
    return '${String.fromCharCode('a'.codeUnitAt(0) + file)}$rank';
  }

  static int? squareNameToVisualIndex(String square, bool flipped) {
    final index = squareNameToIndex(square);
    if (index == null) return null;

    return flipped ? 63 - index : index;
  }

  static Offset visualIndexToCenterOffset(int visualIndex, Size size) {
    final squareSize = size.shortestSide / 8;
    final row = visualIndex ~/ 8;
    final col = visualIndex % 8;

    return Offset(
      (col + 0.5) * squareSize,
      (row + 0.5) * squareSize,
    );
  }
}

class _BestMoveArrowPainter extends CustomPainter {
  final String fromSquare;
  final String toSquare;
  final bool flipped;

  const _BestMoveArrowPainter({
    required this.fromSquare,
    required this.toSquare,
    required this.flipped,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fromVisualIndex =
        ChessBoardView.squareNameToVisualIndex(fromSquare, flipped);
    final toVisualIndex =
        ChessBoardView.squareNameToVisualIndex(toSquare, flipped);

    if (fromVisualIndex == null || toVisualIndex == null) return;

    final from = ChessBoardView.visualIndexToCenterOffset(
      fromVisualIndex,
      size,
    );
    final to = ChessBoardView.visualIndexToCenterOffset(toVisualIndex, size);
    final vector = to - from;
    final distance = vector.distance;

    if (distance <= 0) return;

    final squareSize = size.shortestSide / 8;
    final direction = vector / distance;
    final start = from + direction * (squareSize * 0.16);
    final tip = to - direction * (squareSize * 0.12);
    final lineEnd = tip - direction * (squareSize * 0.18);
    final perpendicular = Offset(-direction.dy, direction.dx);
    final strokeWidth = (squareSize * 0.16).clamp(8.0, 18.0);
    final arrowLength = (squareSize * 0.36).clamp(18.0, 36.0);
    final arrowWidth = arrowLength * 0.64;
    final color = const Color(0xB8A6E22E);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, lineEnd, linePaint);

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - direction.dx * arrowLength + perpendicular.dx * arrowWidth,
        tip.dy - direction.dy * arrowLength + perpendicular.dy * arrowWidth,
      )
      ..lineTo(
        tip.dx - direction.dx * arrowLength - perpendicular.dx * arrowWidth,
        tip.dy - direction.dy * arrowLength - perpendicular.dy * arrowWidth,
      )
      ..close();

    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, headPaint);
  }

  @override
  bool shouldRepaint(covariant _BestMoveArrowPainter oldDelegate) {
    return oldDelegate.fromSquare != fromSquare ||
        oldDelegate.toSquare != toSquare ||
        oldDelegate.flipped != flipped;
  }
}

class _BoardSquare extends StatelessWidget {
  final int boardIndex;
  final int file;
  final int rank;
  final int visualRow;
  final int visualCol;
  final bool isDarkSquare;
  final bool isSelected;
  final bool isLegalTarget;
  final bool isLastMove;
  final bool isCheckedKing;
  final bool isCheckmate;
  final Widget? piece;

  const _BoardSquare({
    required this.boardIndex,
    required this.file,
    required this.rank,
    required this.visualRow,
    required this.visualCol,
    required this.isDarkSquare,
    required this.isSelected,
    required this.isLegalTarget,
    required this.isLastMove,
    required this.isCheckedKing,
    required this.isCheckmate,
    required this.piece,
  });

  @override
  Widget build(BuildContext context) {
    final coordinateColor = ChessBoardView.coordinateColor(isDarkSquare);
    final fileLabel = String.fromCharCode('a'.codeUnitAt(0) + file);
    final rankLabel = '$rank';

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: ChessBoardView.woodDecoration(isDarkSquare, boardIndex),
        ),
        _WoodGrainOverlay(isDarkSquare: isDarkSquare),
        if (isLastMove)
          const ColoredBox(color: ChessBoardView._lastMoveOverlay),
        if (isSelected)
          const ColoredBox(color: ChessBoardView._selectedOverlay),
        if (isLegalTarget && piece == null)
          const Center(
            child: FractionallySizedBox(
              widthFactor: 0.22,
              heightFactor: 0.22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ChessBoardView._legalMarker,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        if (isCheckedKing)
          ColoredBox(
            color:
                isCheckmate ? const Color(0xAA7F1D1D) : const Color(0x88EF4444),
          ),
        if (piece != null)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.84,
              heightFactor: 0.84,
              child: piece,
            ),
          ),
        if (isLegalTarget && piece != null)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.68,
              heightFactor: 0.68,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ChessBoardView._legalMarker,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        if (visualCol == 7)
          Positioned(
            top: 4,
            right: 5,
            child: _CoordinateLabel(
              text: rankLabel,
              color: coordinateColor,
            ),
          ),
        if (visualRow == 7)
          Positioned(
            left: 5,
            bottom: 3,
            child: _CoordinateLabel(
              text: fileLabel,
              color: coordinateColor,
            ),
          ),
      ],
    );
  }
}

class _WoodGrainOverlay extends StatelessWidget {
  final bool isDarkSquare;

  const _WoodGrainOverlay({required this.isDarkSquare});

  @override
  Widget build(BuildContext context) {
    final lightAlpha = isDarkSquare ? 22 : 28;
    final darkAlpha = isDarkSquare ? 22 : 14;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withAlpha(0),
            Colors.white.withAlpha(lightAlpha),
            Colors.black.withAlpha(darkAlpha),
            Colors.white.withAlpha(0),
          ],
          stops: const [0.0, 0.32, 0.68, 1.0],
        ),
      ),
    );
  }
}

class _CoordinateLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _CoordinateLabel({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        height: 1,
        shadows: const [
          Shadow(
            color: Color(0x66000000),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
