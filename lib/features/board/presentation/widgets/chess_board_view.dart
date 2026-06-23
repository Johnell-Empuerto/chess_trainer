import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:chess_trainer/core/chess/game.dart';
import 'package:chess_trainer/features/board/domain/board_annotation.dart';

class ChessBoardView extends StatefulWidget {
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
  static const Color _legalMarker = Color(0xA832C9A0);
  static const Color _legalMarkerStroke = Color(0xD80B4F45);

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
  final List<BoardArrow> userArrows;
  final List<BoardCircle> userCircles;
  final Function(int) onSquareTap;
  final void Function(int fromSquare, int toSquare) onPieceDropped;
  final void Function(String fromSquare, String toSquare) onUserArrowDrawn;
  final void Function(String square) onUserCircleDrawn;

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
    required this.userArrows,
    required this.userCircles,
    required this.onSquareTap,
    required this.onPieceDropped,
    required this.onUserArrowDrawn,
    required this.onUserCircleDrawn,
  });

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();

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

class _ChessBoardViewState extends State<ChessBoardView> {
  String? _rightDragStartSquare;
  Offset? _rightDragCurrentOffset;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ChessBoardView._boardBorder,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.biggest.shortestSide;
            final squareSize = boardSize / 8;
            final feedbackSize = (squareSize * 0.9).clamp(52.0, 96.0);
            final checkedKingIndex = widget.checkedKingSquare == null
                ? null
                : ChessBoardView.squareNameToIndex(
                    widget.checkedKingSquare!,
                  );

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _handlePointerDown(event, boardSize),
              onPointerMove: (event) => _handlePointerMove(event, boardSize),
              onPointerUp: (event) => _handlePointerUp(event, boardSize),
              onPointerCancel: (_) => _cancelRightDrag(),
              child: SizedBox.square(
                dimension: boardSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var visualIndex = 0; visualIndex < 64; visualIndex++)
                      _buildSquare(
                        visualIndex: visualIndex,
                        squareSize: squareSize,
                        feedbackSize: feedbackSize.toDouble(),
                        checkedKingIndex: checkedKingIndex,
                      ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _BoardAnnotationPainter(
                          arrows: widget.userArrows,
                          circles: widget.userCircles,
                          flipped: widget.flipped,
                          previewFromSquare: _rightDragStartSquare,
                          previewOffset: _rightDragCurrentOffset,
                        ),
                      ),
                    ),
                    if (widget.bestMoveFrom != null &&
                        widget.bestMoveTo != null)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _BestMoveArrowPainter(
                            fromSquare: widget.bestMoveFrom!,
                            toSquare: widget.bestMoveTo!,
                            flipped: widget.flipped,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSquare({
    required int visualIndex,
    required double squareSize,
    required double feedbackSize,
    required int? checkedKingIndex,
  }) {
    final visualRow = visualIndex ~/ 8;
    final visualCol = visualIndex % 8;
    final boardIndex = widget.flipped ? 63 - visualIndex : visualIndex;
    final piece = widget.game.board[boardIndex];
    final row = boardIndex ~/ 8;
    final col = boardIndex % 8;
    final rank = 8 - row;

    final isDarkSquare = (row + col) % 2 == 1;
    final isSelected = widget.selectedSquare == boardIndex;
    final isLegalTarget = widget.legalTargets.contains(boardIndex);
    final isLastMove =
        boardIndex == widget.lastMoveFrom || boardIndex == widget.lastMoveTo;
    final isCheckedKing = checkedKingIndex == boardIndex;
    final canDragPiece = piece != null &&
        piece.color == widget.game.turn.displayName.toLowerCase();

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
      isCheckmate: widget.isCheckmate,
      piece: piece?.icon,
    );

    Widget child = squareContent;

    if (canDragPiece) {
      child = Draggable<int>(
        data: boardIndex,
        allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox.square(
            dimension: feedbackSize,
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

    return Positioned(
      left: visualCol * squareSize,
      top: visualRow * squareSize,
      width: squareSize,
      height: squareSize,
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) {
          final fromSquare = details.data;
          if (fromSquare == boardIndex) return false;
          return true;
        },
        onAcceptWithDetails: (details) {
          widget.onPieceDropped(details.data, boardIndex);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSquareTap(boardIndex),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (isHovering)
                  const ColoredBox(color: ChessBoardView._hoverOverlay),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event, double boardSize) {
    if ((event.buttons & kSecondaryMouseButton) == 0) return;

    final square = _squareAtLocalPosition(event.localPosition, boardSize);
    if (square == null) return;

    setState(() {
      _rightDragStartSquare = square;
      _rightDragCurrentOffset = event.localPosition;
    });
  }

  void _handlePointerMove(PointerMoveEvent event, double boardSize) {
    if (_rightDragStartSquare == null ||
        (event.buttons & kSecondaryMouseButton) == 0) {
      return;
    }

    final clampedOffset = Offset(
      event.localPosition.dx.clamp(0.0, boardSize),
      event.localPosition.dy.clamp(0.0, boardSize),
    );

    setState(() {
      _rightDragCurrentOffset = clampedOffset;
    });
  }

  void _handlePointerUp(PointerUpEvent event, double boardSize) {
    final startSquare = _rightDragStartSquare;
    if (startSquare == null) return;

    final endSquare =
        _squareAtLocalPosition(event.localPosition, boardSize) ?? startSquare;

    setState(() {
      _rightDragStartSquare = null;
      _rightDragCurrentOffset = null;
    });

    if (startSquare == endSquare) {
      widget.onUserCircleDrawn(startSquare);
    } else {
      widget.onUserArrowDrawn(startSquare, endSquare);
    }
  }

  void _cancelRightDrag() {
    if (_rightDragStartSquare == null && _rightDragCurrentOffset == null) {
      return;
    }

    setState(() {
      _rightDragStartSquare = null;
      _rightDragCurrentOffset = null;
    });
  }

  String? _squareAtLocalPosition(Offset localPosition, double boardSize) {
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > boardSize ||
        localPosition.dy > boardSize) {
      return null;
    }

    final squareSize = boardSize / 8;
    final visualCol = (localPosition.dx / squareSize).floor().clamp(0, 7);
    final visualRow = (localPosition.dy / squareSize).floor().clamp(0, 7);
    final visualIndex = visualRow * 8 + visualCol;
    final boardIndex = widget.flipped ? 63 - visualIndex : visualIndex;

    return ChessBoardView.indexToSquareName(boardIndex);
  }
}

class _BoardAnnotationPainter extends CustomPainter {
  final List<BoardArrow> arrows;
  final List<BoardCircle> circles;
  final bool flipped;
  final String? previewFromSquare;
  final Offset? previewOffset;

  const _BoardAnnotationPainter({
    required this.arrows,
    required this.circles,
    required this.flipped,
    required this.previewFromSquare,
    required this.previewOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.shortestSide / 8;

    for (final circle in circles) {
      final center = _centerForSquare(circle.square, size);
      if (center == null) continue;
      _drawCircle(canvas, center, squareSize, circle.color);
    }

    for (final arrow in arrows) {
      final from = _centerForSquare(arrow.fromSquare, size);
      final to = _centerForSquare(arrow.toSquare, size);
      if (from == null || to == null) continue;
      _drawArrow(canvas, from, to, squareSize, arrow.color);
    }

    final previewFrom = previewFromSquare;
    final previewTo = previewOffset;
    if (previewFrom != null && previewTo != null) {
      final from = _centerForSquare(previewFrom, size);
      if (from != null) {
        final endSquare = _squareNameForOffset(previewTo, size);
        if (endSquare == null || endSquare == previewFrom) {
          _drawCircle(
            canvas,
            from,
            squareSize,
            const Color(0xAA16A085),
          );
        } else {
          _drawArrow(
            canvas,
            from,
            previewTo,
            squareSize,
            const Color(0xAA16A085),
          );
        }
      }
    }
  }

  Offset? _centerForSquare(String square, Size size) {
    final visualIndex = ChessBoardView.squareNameToVisualIndex(
      square,
      flipped,
    );
    if (visualIndex == null) return null;

    return ChessBoardView.visualIndexToCenterOffset(visualIndex, size);
  }

  String? _squareNameForOffset(Offset offset, Size size) {
    final boardSize = size.shortestSide;
    if (offset.dx < 0 ||
        offset.dy < 0 ||
        offset.dx > boardSize ||
        offset.dy > boardSize) {
      return null;
    }

    final squareSize = boardSize / 8;
    final visualCol = (offset.dx / squareSize).floor().clamp(0, 7);
    final visualRow = (offset.dy / squareSize).floor().clamp(0, 7);
    final visualIndex = visualRow * 8 + visualCol;
    final boardIndex = flipped ? 63 - visualIndex : visualIndex;

    return ChessBoardView.indexToSquareName(boardIndex);
  }

  void _drawCircle(
    Canvas canvas,
    Offset center,
    double squareSize,
    Color color,
  ) {
    final radius = squareSize * 0.36;
    final strokeWidth = (squareSize * 0.065).clamp(4.0, 8.0);

    final fillPaint = Paint()
      ..color = color.withAlpha(30)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, strokePaint);
  }

  void _drawArrow(
    Canvas canvas,
    Offset from,
    Offset to,
    double squareSize,
    Color color,
  ) {
    final vector = to - from;
    final distance = vector.distance;

    if (distance <= squareSize * 0.2) return;

    final direction = vector / distance;
    final start = from + direction * (squareSize * 0.18);
    final tip = to - direction * (squareSize * 0.16);
    final lineEnd = tip - direction * (squareSize * 0.18);
    final perpendicular = Offset(-direction.dy, direction.dx);
    final strokeWidth = (squareSize * 0.13).clamp(7.0, 16.0);
    final arrowLength = (squareSize * 0.34).clamp(17.0, 34.0);
    final arrowWidth = arrowLength * 0.64;

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
  bool shouldRepaint(covariant _BoardAnnotationPainter oldDelegate) {
    return true;
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
        if (isLegalTarget && piece == null) const _LegalMoveDot(),
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
        if (isLegalTarget && piece != null) const _LegalCaptureRing(),
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

class _LegalMoveDot extends StatelessWidget {
  const _LegalMoveDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.26,
        heightFactor: 0.26,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ChessBoardView._legalMarker,
            shape: BoxShape.circle,
            border: Border.all(
              color: ChessBoardView._legalMarkerStroke,
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalCaptureRing extends StatelessWidget {
  const _LegalCaptureRing();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final squareSize = constraints.biggest.shortestSide;
        final strokeWidth = (squareSize * 0.06).clamp(3.0, 6.0);

        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.78,
            heightFactor: 0.78,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ChessBoardView._legalMarker,
                  width: strokeWidth,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 5,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
