import 'package:chess/chess.dart' as rules;

import 'package:chess_trainer/core/chess/piece.dart';

class Turn {
  final String displayName;

  const Turn._(this.displayName);

  static const white = Turn._('White');
  static const black = Turn._('Black');

  Turn get opposite => this == white ? black : white;
}

class Game {
  static const startingFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  final rules.Chess _chess;
  final List<Piece?> board = List.generate(64, (_) => null);
  final List<String> moveHistory = [];
  final List<MoveHistoryEntry> moveHistoryEntries = [];

  Game._(this._chess) {
    _syncFromRules();
  }

  static Game initial() {
    return Game._(rules.Chess());
  }

  static Game fromFen(String fen) {
    return Game._(rules.Chess.fromFEN(fen));
  }

  bool get isCheckmate => _chess.in_checkmate;
  bool get isStalemate => _chess.in_stalemate;
  bool get inCheck => _chess.in_check;
  bool get isCheck => inCheck;
  bool get canUndo => _chess.getHistory().isNotEmpty;
  int get moveNumber => _chess.move_number;
  String get fen => _chess.fen;
  String get turnColor => turn.displayName.toLowerCase();

  String? get checkedKingSquareName {
    if (!isCheck && !isCheckmate) return null;

    for (var index = 0; index < board.length; index++) {
      final piece = board[index];

      if (piece != null && piece.type == 'king' && piece.color == turnColor) {
        return squareName(index);
      }
    }

    return null;
  }

  int? get checkedKingIndex {
    final square = checkedKingSquareName;
    return square == null ? null : squareIndex(square);
  }

  Turn get turn {
    return _chess.turn == rules.Color.WHITE ? Turn.white : Turn.black;
  }

  Piece? pieceAt(int square) {
    if (!_isValidSquare(square)) return null;
    return board[square];
  }

  String? playFromTo(int from, int to) {
    if (!_isValidSquare(from) || !_isValidSquare(to)) return null;

    final fromName = squareName(from);
    final toName = squareName(to);
    final move = _matchingMove(fromName, toName);

    if (move == null) return null;

    final san = move['san'] as String;
    final success = _playMoveMap(fromName, toName, 'q');

    if (!success) return null;

    _syncFromRules();
    return san;
  }

  String? playUci(String uci) {
    if (uci.length < 4) return null;

    final fromName = uci.substring(0, 2);
    final toName = uci.substring(2, 4);
    final promotion =
        uci.length >= 5 ? uci.substring(4, 5).toLowerCase() : null;

    if (squareIndex(fromName) == null || squareIndex(toName) == null) {
      return null;
    }

    final move = _matchingMove(fromName, toName, promotion);
    if (move == null) return null;

    final san = move['san'] as String;
    final success = _playMoveMap(fromName, toName, promotion);

    if (!success) return null;

    _syncFromRules();
    return san;
  }

  List<int> legalMovesFrom(int square) {
    if (!_isValidSquare(square)) return [];

    final moves = _verboseMovesFrom(squareName(square));
    final targets = <int>{};

    for (final move in moves) {
      final target = squareIndex(move['to'] as String);
      if (target != null) {
        targets.add(target);
      }
    }

    return targets.toList()..sort();
  }

  List<String> legalMoveNamesFrom(int square) {
    return legalMovesFrom(square).map(squareName).toList();
  }

  void undoMove() {
    final undoneMove = _chess.undo();
    if (undoneMove == null) return;

    _syncFromRules();
  }

  void _syncFromRules() {
    for (var index = 0; index < 64; index++) {
      final rulesPiece = _chess.get(squareName(index));
      board[index] = rulesPiece == null
          ? null
          : Piece(
              _pieceTypeName(rulesPiece.type),
              _pieceColorName(rulesPiece.color),
            );
    }

    moveHistory
      ..clear()
      ..addAll(_formattedMoveHistory());

    moveHistoryEntries
      ..clear()
      ..addAll(_moveHistoryEntries());
  }

  List<Map<String, dynamic>> _verboseMovesFrom(String squareName) {
    return _chess.moves({
      'square': squareName,
      'verbose': true,
    }).cast<Map<String, dynamic>>();
  }

  bool _playMoveMap(String from, String to, String? promotion) {
    return _chess.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });
  }

  Map<String, dynamic>? _matchingMove(
    String from,
    String to, [
    String? promotion,
  ]) {
    final moves = _verboseMovesFrom(from)
        .where((move) => move['from'] == from && move['to'] == to)
        .toList();

    if (moves.isEmpty) return null;

    if (promotion != null) {
      final promotionSuffix = '=${promotion.toUpperCase()}';
      for (final move in moves) {
        if ((move['san'] as String).contains(promotionSuffix)) {
          return move;
        }
      }
      return null;
    }

    return moves.firstWhere(
      (move) => (move['san'] as String).contains('=Q'),
      orElse: () => moves.first,
    );
  }

  List<String> _formattedMoveHistory() {
    return _moveHistoryEntries().map((entry) => entry.displayText).toList();
  }

  List<MoveHistoryEntry> _moveHistoryEntries() {
    final sanMoves = _chess.getHistory().cast<String>();
    final entries = <MoveHistoryEntry>[];

    for (var i = 0; i < sanMoves.length; i += 2) {
      final moveNumber = (i ~/ 2) + 1;
      final whiteMove = sanMoves[i];
      final blackMove = i + 1 < sanMoves.length ? sanMoves[i + 1] : null;

      entries.add(
        MoveHistoryEntry(
          moveNumber: moveNumber,
          whiteSan: whiteMove,
          blackSan: blackMove,
        ),
      );
    }

    return entries;
  }

  static String squareName(int index) {
    if (!_isValidSquare(index)) return '';

    final file = index % 8;
    final rank = 8 - (index ~/ 8);
    return '${String.fromCharCode('a'.codeUnitAt(0) + file)}$rank';
  }

  static int? squareIndex(String name) {
    if (name.length != 2) return null;

    final file = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(name[1]);

    if (file < 0 || file > 7 || rank == null || rank < 1 || rank > 8) {
      return null;
    }

    return (8 - rank) * 8 + file;
  }

  static bool _isValidSquare(int square) {
    return square >= 0 && square < 64;
  }

  static String _pieceColorName(rules.Color color) {
    return color == rules.Color.WHITE ? 'white' : 'black';
  }

  static String _pieceTypeName(rules.PieceType type) {
    switch (type.name) {
      case 'p':
        return 'pawn';
      case 'n':
        return 'knight';
      case 'b':
        return 'bishop';
      case 'r':
        return 'rook';
      case 'q':
        return 'queen';
      case 'k':
        return 'king';
      default:
        return '';
    }
  }
}

class MoveHistoryEntry {
  final int moveNumber;
  final String whiteSan;
  final String? blackSan;

  const MoveHistoryEntry({
    required this.moveNumber,
    required this.whiteSan,
    required this.blackSan,
  });

  String get displayText {
    return '$moveNumber. $whiteSan${blackSan == null ? '' : ' $blackSan'}';
  }

  bool get hasBlackMove => blackSan != null;
}
