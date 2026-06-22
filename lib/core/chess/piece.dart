import 'package:flutter/material.dart';

/// Represents a chess piece.
class Piece {
  final String type; // pawn, rook, knight, bishop, queen, king
  final String color; // white, black

  const Piece(this.type, this.color);

  String get displayName => '${color[0].toUpperCase()}$type';

  String get assetPath => 'assets/pieces/$color-$type.png';

  String get legacyAssetPath => 'assets/pieces/${color}_$type.png';

  /// Unicode chess symbol used as a temporary fallback when PNG assets are missing.
  String get symbol {
    final isWhite = color == 'white';

    switch (type) {
      case 'king':
        return isWhite ? '\u2654' : '\u265A';
      case 'queen':
        return isWhite ? '\u2655' : '\u265B';
      case 'rook':
        return isWhite ? '\u2656' : '\u265C';
      case 'bishop':
        return isWhite ? '\u2657' : '\u265D';
      case 'knight':
        return isWhite ? '\u2658' : '\u265E';
      case 'pawn':
        return isWhite ? '\u2659' : '\u265F';
      default:
        return '';
    }
  }

  /// Returns the widget icon for the piece.
  ///
  /// Place PNG files in assets/pieces/ using names like white-king.png and
  /// black-pawn.png. The fallback keeps the board usable until those files exist.
  Widget get icon {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          legacyAssetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return _FallbackPieceSymbol(
              color: color,
              symbol: symbol,
            );
          },
        );
      },
    );
  }
}

class _FallbackPieceSymbol extends StatelessWidget {
  final String color;
  final String symbol;

  const _FallbackPieceSymbol({
    required this.color,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final isWhite = color == 'white';

    return FittedBox(
      fit: BoxFit.contain,
      child: Text(
        symbol,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: isWhite ? Colors.white : const Color(0xFF111111),
          shadows: [
            Shadow(
              color: isWhite ? Colors.black87 : Colors.white70,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
            Shadow(
              color: isWhite ? Colors.black45 : Colors.black38,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
