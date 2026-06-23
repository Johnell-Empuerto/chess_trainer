/// A chess move.
///
/// Squares are indexed 0..63 using the formula:
///   index = rankFromEight * 8 + file
/// where rankFromEight 0 = rank 8, file 0 = 'a'.
/// So a8 = 0, h8 = 7, a1 = 56, h1 = 63.
class Move {
  final int from;
  final int to;
  final PieceType? promotion;

  const Move({required this.from, required this.to, this.promotion});

  String get fromAlgebraic => _squareName(from);
  String get toAlgebraic => _squareName(to);

  /// UCI-style representation, e.g. "e2e4" or "e7e8q".
  String get uci {
    var s = '${fromAlgebraic}${toAlgebraic}';
    if (promotion != null) {
      final promoLetter = {
        PieceType.queen: 'q',
        PieceType.rook: 'r',
        PieceType.bishop: 'b',
        PieceType.knight: 'n',
      };
      s += promoLetter[promotion!]!;
    }
    return s;
  }

  @override
  String toString() => uci;
}

class PieceType {
  final String name;

  const PieceType._(this.name);

  static const queen = PieceType._('queen');
  static const rook = PieceType._('rook');
  static const bishop = PieceType._('bishop');
  static const knight = PieceType._('knight');
}

/// Convert a square index (0..63) to algebraic name, e.g. 60 -> 'e1'.
String squareName(int index) {
  final file = index % 8;
  final rank = 8 - (index ~/ 8);
  return '${String.fromCharCode('a'.codeUnitAt(0) + file)}$rank';
}

/// Convert algebraic name to square index, e.g. 'e1' -> 60.
int squareIndex(String name) {
  final file = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(name[1]) - 1;
  return (7 - rank) * 8 + file;
}

// Private helper used by Move.
String _squareName(int index) => squareName(index);

enum MoveColor {
  white,
  black,
}

class MoveRecord {
  final int id;
  final String san;
  final String uci;
  final String fenBefore;
  final String fenAfter;
  final int moveNumber;
  final MoveColor color;
  final int? parentId;
  final List<int> children;

  const MoveRecord({
    required this.id,
    required this.san,
    required this.uci,
    required this.fenBefore,
    required this.fenAfter,
    required this.moveNumber,
    required this.color,
    this.parentId,
    this.children = const [],
  });

  bool get isWhiteMove => color == MoveColor.white;
  bool get isBlackMove => color == MoveColor.black;
}
