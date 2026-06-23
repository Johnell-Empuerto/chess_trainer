import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chess_trainer/core/chess/game.dart';
import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/board/domain/board_annotation.dart';
import 'package:chess_trainer/features/board/presentation/widgets/chess_board_view.dart';
import 'package:chess_trainer/features/board/presentation/widgets/info_panel.dart';
import 'package:chess_trainer/features/coach/data/ai_explainer_service.dart';
import 'package:chess_trainer/features/coach/data/stockfish_coach_service.dart';
import 'package:chess_trainer/features/computer/domain/computer_level.dart';
import 'package:chess_trainer/features/computer/domain/computer_play_mode.dart';
import 'package:chess_trainer/features/computer/presentation/play_computer_dialog.dart';
import 'package:chess_trainer/features/engine/data/stockfish_engine_service.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/engine/presentation/widgets/evaluation_bar.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/data/opening_name_service.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';

/// Interactive chess board screen.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  static const bool _debugBoard = false;

  late Game _game;
  late final FocusNode _keyboardFocusNode;
  final StockfishEngineService _engineService = StockfishEngineService();
  final OpeningExplorerRepository _explorerRepository =
      OpeningExplorerRepository();
  final OpeningNameService _openingNameService = OpeningNameService();
  late final StockfishCoachService _coachService = StockfishCoachService(
    _engineService,
  );
  final AiExplainerService _aiService = AiExplainerService();
  final Map<String, MoveNode> _moveTree = {
    MoveNode.rootId: MoveNode.root(Game.startingFen),
  };
  final List<BoardArrow> _userArrows = [];
  final List<BoardCircle> _userCircles = [];
  BoardReviewOverlay _reviewOverlay = const BoardReviewOverlay.empty();
  bool _flipped = false;
  int? _selectedSquare;
  List<int> _legalTargets = [];
  int? _lastMoveFrom;
  int? _lastMoveTo;
  bool _engineRunning = false;
  bool _engineStarting = false;
  bool _isAnalyzing = false;
  EngineAnalysisResult? _engineResult;
  String? _bestMoveFrom;
  String? _bestMoveTo;
  String? _engineError;
  ComputerPlayMode _computerMode = ComputerPlayMode.off;
  String? _humanColor;
  String? _computerColor;
  ComputerLevel _computerLevel = ComputerLevel.normal;
  bool _computerThinking = false;
  String? _computerError;
  String? _hintMoveFrom;
  String? _hintMoveTo;
  EngineAnalysisResult? _hintResult;
  StreamSubscription<EngineAnalysisResult>? _engineSubscription;
  int? _activeEngineSearchId;
  String? _activeEngineFen;
  int _engineControlRequestId = 0;
  int _computerRequestId = 0;
  int _hintRequestId = 0;
  String? _computerActiveNodeId;
  int _nextMoveNodeId = 0;
  String _currentNodeId = MoveNode.rootId;
  String _mainLineLeafId = MoveNode.rootId;

  MoveNode get _currentNode => _moveTree[_currentNodeId]!;
  MoveNode? get _currentMoveNode =>
      _currentNodeId == MoveNode.rootId ? null : _currentNode;
  bool get _isAtMainLineEnd => _currentNodeId == _mainLineLeafId;
  bool get _isComputerModeRunning => _computerMode.isActive;
  bool get _isViewingComputerActiveNode =>
      _computerActiveNodeId == null || _computerActiveNodeId == _currentNodeId;
  bool get _canUserMoveNow {
    if (_computerMode == ComputerPlayMode.off) return true;
    if (_computerMode == ComputerPlayMode.gameOver) return false;
    if (_computerThinking || !_isViewingComputerActiveNode) return false;
    return _humanColor == _game.turnColor;
  }

  bool get _canRequestComputerHint {
    if (!_isComputerModeRunning) return false;
    if (_computerThinking || !_isViewingComputerActiveNode) return false;
    if (_game.isCheckmate || _game.isStalemate) return false;
    return _humanColor == _game.turnColor;
  }

  bool get _shouldComputerMoveNow {
    if (!_isComputerModeRunning) return false;
    if (_computerThinking || !_isViewingComputerActiveNode) return false;
    if (_game.isCheckmate || _game.isStalemate) return false;
    return _computerColor == _game.turnColor;
  }

  String get _computerStatusText {
    if (_computerMode == ComputerPlayMode.off) return '';
    if (_game.isCheckmate) return 'Checkmate';
    if (_game.isStalemate) return 'Stalemate';
    if (!_isViewingComputerActiveNode) {
      return 'Viewing previous position';
    }
    if (_computerThinking) return 'Computer is thinking...';
    if (_hintResult != null &&
        _hintMoveFrom != null &&
        _hintMoveTo != null &&
        _humanColor == _game.turnColor) {
      return 'Hint shown: ${_hintResult!.bestMoveUci}';
    }
    if (_humanColor == _game.turnColor) return 'Your move';
    return 'Computer to move';
  }

  List<String> get _displayedSanMoveHistory {
    return _currentMovePath
        .map((node) => node.san)
        .where((san) => san.isNotEmpty)
        .toList(growable: false);
  }

  List<MoveNode> get _currentMovePath {
    final nodes = <MoveNode>[];
    var nodeId = _currentNodeId;

    while (nodeId != MoveNode.rootId) {
      final node = _moveTree[nodeId];
      if (node == null) break;
      nodes.add(node);
      nodeId = node.parentId ?? MoveNode.rootId;
    }

    return nodes.reversed.toList(growable: false);
  }

  List<String> get _mainLineNodeIds {
    final nodeIds = <String>[];
    var parentId = MoveNode.rootId;

    while (true) {
      final childId = _mainChildId(parentId);
      if (childId == null) break;
      nodeIds.add(childId);
      parentId = childId;
    }

    return nodeIds;
  }

  @override
  void initState() {
    super.initState();
    _game = Game.initial();
    _keyboardFocusNode = FocusNode(debugLabel: 'Board keyboard navigation');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
    _engineSubscription = _engineService.analysisStream.listen(
      _handleEngineUpdate,
      onError: _handleEngineStreamError,
    );
    _aiService.initialize();
  }

  @override
  void dispose() {
    unawaited(_engineSubscription?.cancel());
    _keyboardFocusNode.dispose();
    _engineService.dispose();
    _aiService.dispose();
    _explorerRepository.dispose();
    super.dispose();
  }

  void _onSquareTap(int square) {
    if (!_canUserMoveNow) {
      if (_selectedSquare != null || _legalTargets.isNotEmpty) {
        setState(() {
          _selectedSquare = null;
          _legalTargets = [];
        });
      }
      return;
    }

    final piece = _game.board[square];

    if (_selectedSquare != null) {
      if (_legalTargets.contains(square)) {
        final fromSquare = _selectedSquare!;
        _playFromTo(fromSquare, square);
        return;
      }

      if (piece != null &&
          piece.color == _game.turn.displayName.toLowerCase()) {
        final legalMoves = _game.legalMovesFrom(square);
        _debugSelection(square, legalMoves);
        setState(() {
          _selectedSquare = square;
          _legalTargets = legalMoves;
        });
        return;
      }

      if (_debugBoard) {
        debugPrint(
          'Move result fail: ${Game.squareName(_selectedSquare!)} to '
          '${Game.squareName(square)}',
        );
      }
      setState(() {
        _selectedSquare = null;
        _legalTargets = [];
      });
      return;
    }

    if (piece != null && piece.color == _game.turn.displayName.toLowerCase()) {
      final legalMoves = _game.legalMovesFrom(square);
      _debugSelection(square, legalMoves);
      setState(() {
        _selectedSquare = square;
        _legalTargets = legalMoves;
      });
    }
  }

  void _onPieceDropped(int fromSquare, int toSquare) {
    if (!_canUserMoveNow) return;

    if (_debugBoard) {
      final legalMoves = _game.legalMovesFrom(fromSquare);
      debugPrint('Drag drop fromSquare: ${Game.squareName(fromSquare)}');
      debugPrint('Drag drop toSquare: ${Game.squareName(toSquare)}');
      debugPrint(
        'Drag drop legal moves: ${legalMoves.map(Game.squareName).join(', ')}',
      );
    }

    _playFromTo(fromSquare, toSquare);
  }

  void _debugSelection(int square, List<int> legalMoves) {
    if (!_debugBoard) return;

    debugPrint('Selected square: ${Game.squareName(square)}');
    debugPrint(
      'Legal moves from ${Game.squareName(square)}: '
      '${legalMoves.map(Game.squareName).join(', ')}',
    );
  }

  void _debugMoveResult(int fromSquare, int toSquare, String? san) {
    if (!_debugBoard) return;

    final fromName = Game.squareName(fromSquare);
    final toName = Game.squareName(toSquare);

    debugPrint('Target square: $toName');
    debugPrint(
      san == null
          ? 'Move result fail: $fromName to $toName'
          : 'Move result success: $fromName to $toName ($san)',
    );
    debugPrint('Current FEN after move: ${_game.fen}');
  }

  void _playFromTo(int fromSquare, int toSquare) {
    if (!_canUserMoveNow) return;

    final fenBefore = _game.fen;
    final moveNumber = _game.moveNumber;
    final moveColor =
        _game.turn == Turn.white ? MoveColor.white : MoveColor.black;
    final san = _game.playFromTo(fromSquare, toSquare);
    _debugMoveResult(fromSquare, toSquare, san);

    if (san == null) return;

    final uci = _uciFromSquares(fromSquare, toSquare, san);
    final fenAfter = _game.fen;

    setState(() {
      _clearPositionAnalysis();
      _clearHintInState();
      _clearReviewOverlayInState();
      _commitPlayedMove(
        san: san,
        uci: uci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        moveNumber: moveNumber,
        color: moveColor,
      );
      _lastMoveFrom = fromSquare;
      _lastMoveTo = toSquare;
      _selectedSquare = null;
      _legalTargets = [];
      _syncComputerAfterMoveInState();
    });
    _afterMoveCommitted();
  }

  void _onExplorerMoveSelected(ExplorerMoveStat moveStat) {
    if (!_canUserMoveNow) return;

    if (moveStat.moveUci.length < 4) {
      debugPrint('Explorer move invalid: ${moveStat.moveUci}');
      return;
    }

    final fromSquare = Game.squareIndex(moveStat.moveUci.substring(0, 2));
    final toSquare = Game.squareIndex(moveStat.moveUci.substring(2, 4));

    if (fromSquare == null || toSquare == null) {
      debugPrint('Explorer move invalid: ${moveStat.moveUci}');
      return;
    }

    final fenBefore = _game.fen;
    final moveNumber = _game.moveNumber;
    final moveColor =
        _game.turn == Turn.white ? MoveColor.white : MoveColor.black;
    final san = _game.playUci(moveStat.moveUci);
    _debugMoveResult(fromSquare, toSquare, san);

    if (san != null) {
      final fenAfter = _game.fen;

      setState(() {
        _clearPositionAnalysis();
        _clearHintInState();
        _clearReviewOverlayInState();
        _commitPlayedMove(
          san: san,
          uci: moveStat.moveUci,
          fenBefore: fenBefore,
          fenAfter: fenAfter,
          moveNumber: moveNumber,
          color: moveColor,
        );
        _lastMoveFrom = fromSquare;
        _lastMoveTo = toSquare;
        _selectedSquare = null;
        _legalTargets = [];
        _syncComputerAfterMoveInState();
      });
      _afterMoveCommitted();
    }
  }

  void _undo() {
    _goToPreviousMove();
  }

  void _reset() {
    final wasComputerModeActive = _computerMode != ComputerPlayMode.off;

    setState(() {
      _clearPositionAnalysis();
      _stopComputerGameInState();
      _clearReviewOverlayInState();
      _game = Game.initial();
      _moveTree
        ..clear()
        ..addAll({
          MoveNode.rootId: MoveNode.root(Game.startingFen),
        });
      _currentNodeId = MoveNode.rootId;
      _mainLineLeafId = MoveNode.rootId;
      _nextMoveNodeId = 0;
      _selectedSquare = null;
      _legalTargets = [];
      _lastMoveFrom = null;
      _lastMoveTo = null;
      _clearUserAnnotations(updateState: false);
    });
    if (wasComputerModeActive) {
      unawaited(_engineService.cancelCurrentSearch());
    }
    _reanalyzeIfEngineRunning();
  }

  Future<void> _showPlayComputerDialog() async {
    String? openingName;

    try {
      final opening = await _openingNameService.matchOpening(
        currentFen: _game.fen,
        sanMoveHistory: _displayedSanMoveHistory,
      );
      openingName = opening?.displayName;
    } catch (error) {
      debugPrint('opening preview error: $error');
    }

    if (!mounted) return;

    final settings = await showDialog<PlayComputerSettings>(
      context: context,
      builder: (context) {
        return PlayComputerDialog(
          sideToMove: _game.turn.displayName,
          openingName: openingName,
          initialHumanColor: _humanColor ?? _game.turnColor,
          initialLevel: _computerLevel,
        );
      },
    );

    if (settings == null || !mounted) return;
    await _startComputerGame(settings);
  }

  Future<void> _startComputerGame(PlayComputerSettings settings) async {
    if (_engineRunning || _engineStarting || _isAnalyzing) {
      await _stopEngine();
    }

    if (!mounted) return;

    final humanColor = settings.humanColor;
    final computerColor = humanColor == 'white' ? 'black' : 'white';

    setState(() {
      _clearPositionAnalysis();
      _clearHintInState();
      _computerRequestId++;
      _computerMode = ComputerPlayMode.playing;
      _humanColor = humanColor;
      _computerColor = computerColor;
      _computerLevel = settings.level;
      _computerThinking = false;
      _computerError = null;
      _computerActiveNodeId = _currentNodeId;
      _selectedSquare = null;
      _legalTargets = [];
      _setComputerGameOverIfNeededInState();
    });

    _maybeStartComputerMove();
  }

  void _stopComputerGame() {
    setState(_stopComputerGameInState);
    unawaited(_engineService.cancelCurrentSearch());
  }

  void _stopComputerGameInState() {
    _computerRequestId++;
    _computerMode = ComputerPlayMode.off;
    _humanColor = null;
    _computerColor = null;
    _computerThinking = false;
    _computerError = null;
    _computerActiveNodeId = null;
    _selectedSquare = null;
    _legalTargets = [];
    _clearHintInState();
  }

  void _afterMoveCommitted() {
    if (_computerMode != ComputerPlayMode.off) {
      _maybeStartComputerMove();
      return;
    }

    _reanalyzeIfEngineRunning();
  }

  void _syncComputerAfterMoveInState() {
    if (!_isComputerModeRunning) return;

    _computerActiveNodeId = _currentNodeId;
    _computerError = null;
    _setComputerGameOverIfNeededInState();
  }

  void _setComputerGameOverIfNeededInState() {
    if (_computerMode == ComputerPlayMode.off) return;

    if (_game.isCheckmate || _game.isStalemate) {
      _computerMode = ComputerPlayMode.gameOver;
      _computerThinking = false;
    }
  }

  void _clearHintInState() {
    _hintRequestId++;
    _hintMoveFrom = null;
    _hintMoveTo = null;
    _hintResult = null;
  }

  void _maybeStartComputerMove() {
    if (!_shouldComputerMoveNow) return;

    final requestId = ++_computerRequestId;
    final fen = _game.fen;
    final nodeId = _currentNodeId;
    final level = _computerLevel;

    setState(() {
      _computerMode = ComputerPlayMode.thinking;
      _computerThinking = true;
      _computerError = null;
      _selectedSquare = null;
      _legalTargets = [];
      _clearHintInState();
    });

    unawaited(
      _engineService
          .getBestMoveForFen(
        fen: fen,
        level: level,
      )
          .then((result) {
        if (!mounted || requestId != _computerRequestId) return;
        if (_currentNodeId != nodeId ||
            _computerActiveNodeId != nodeId ||
            _game.fen != fen) {
          return;
        }

        final bestMove = result.bestMoveUci;
        if (bestMove == 'none' || bestMove.length < 4) {
          setState(() {
            _computerThinking = false;
            _computerMode = ComputerPlayMode.gameOver;
            _computerError = 'Stockfish did not return a legal move.';
          });
          return;
        }

        final moveApplied = _playComputerUci(bestMove);
        if (!moveApplied && mounted && requestId == _computerRequestId) {
          setState(() {
            _computerThinking = false;
            _computerMode = ComputerPlayMode.playing;
            _computerError = 'Stockfish returned an illegal move: $bestMove';
          });
        }
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint('computer move error: $error');
        if (!mounted || requestId != _computerRequestId) return;

        setState(() {
          _computerThinking = false;
          _computerMode = ComputerPlayMode.playing;
          _computerError = error.toString();
        });
      }),
    );
  }

  bool _playComputerUci(String uci) {
    final fromSquare = Game.squareIndex(uci.substring(0, 2));
    final toSquare = Game.squareIndex(uci.substring(2, 4));

    if (fromSquare == null || toSquare == null) return false;

    final fenBefore = _game.fen;
    final moveNumber = _game.moveNumber;
    final moveColor =
        _game.turn == Turn.white ? MoveColor.white : MoveColor.black;
    final san = _game.playUci(uci);
    _debugMoveResult(fromSquare, toSquare, san);

    if (san == null) return false;

    final fenAfter = _game.fen;

    setState(() {
      _clearPositionAnalysis();
      _clearHintInState();
      _clearReviewOverlayInState();
      _commitPlayedMove(
        san: san,
        uci: uci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        moveNumber: moveNumber,
        color: moveColor,
      );
      _lastMoveFrom = fromSquare;
      _lastMoveTo = toSquare;
      _selectedSquare = null;
      _legalTargets = [];
      _computerThinking = false;
      if (_computerMode == ComputerPlayMode.thinking) {
        _computerMode = ComputerPlayMode.playing;
      }
      _syncComputerAfterMoveInState();
    });

    return true;
  }

  void _requestComputerHint() {
    if (!_canRequestComputerHint) return;

    final requestId = ++_hintRequestId;
    final fen = _game.fen;
    final nodeId = _currentNodeId;
    final level = _computerLevel;

    setState(() {
      _hintMoveFrom = null;
      _hintMoveTo = null;
      _hintResult = null;
      _computerError = null;
    });

    unawaited(
      _engineService
          .getBestMoveForFen(
        fen: fen,
        level: level,
      )
          .then((result) {
        if (!mounted || requestId != _hintRequestId) return;
        if (_game.fen != fen || _currentNodeId != nodeId) return;

        final from = _uciMoveFrom(result.bestMoveUci);
        final to = _uciMoveTo(result.bestMoveUci);

        setState(() {
          _hintResult = result;
          _hintMoveFrom = from;
          _hintMoveTo = to;
          if (from == null || to == null) {
            _computerError = 'No hint move is available in this position.';
          }
        });
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint('computer hint error: $error');
        if (!mounted || requestId != _hintRequestId) return;

        setState(() {
          _hintResult = null;
          _hintMoveFrom = null;
          _hintMoveTo = null;
          _computerError = error.toString();
        });
      }),
    );
  }

  void _commitPlayedMove({
    required String san,
    required String uci,
    required String fenBefore,
    required String fenAfter,
    required int moveNumber,
    required MoveColor color,
  }) {
    final parentId = _currentNodeId;
    final existingChild = _findChildByUci(parentId, uci);
    if (existingChild != null) {
      _currentNodeId = existingChild.id;
      _game = Game.fromFen(existingChild.fenAfter);
      _mainLineLeafId = _computeMainLineLeafId();
      return;
    }

    final nodeId = 'm${++_nextMoveNodeId}';
    final node = MoveNode(
      id: nodeId,
      parentId: parentId,
      san: san,
      uci: uci,
      fenBefore: fenBefore,
      fenAfter: fenAfter,
      moveNumber: moveNumber,
      color: color,
      isMainLine: true,
    );

    _moveTree[nodeId] = node;
    _moveTree[parentId]?.childIds.add(nodeId);
    _setMainChild(parentId, nodeId);
    _currentNodeId = nodeId;
    _mainLineLeafId = _computeMainLineLeafId();
  }

  MoveNode? _findChildByUci(String parentId, String uci) {
    final parent = _moveTree[parentId];
    if (parent == null) return null;

    for (final childId in parent.childIds) {
      final child = _moveTree[childId];
      if (child != null && child.uci == uci) {
        return child;
      }
    }

    return null;
  }

  void _setMainChild(String parentId, String childId) {
    final parent = _moveTree[parentId];
    if (parent == null) return;

    for (final siblingId in parent.childIds) {
      final sibling = _moveTree[siblingId];
      if (sibling != null) {
        sibling.isMainLine = siblingId == childId;
      }
    }
  }

  String? _mainChildId(String parentId) {
    final parent = _moveTree[parentId];
    if (parent == null || parent.childIds.isEmpty) return null;

    for (final childId in parent.childIds) {
      final child = _moveTree[childId];
      if (child?.isMainLine == true) {
        return childId;
      }
    }

    return parent.childIds.first;
  }

  String _computeMainLineLeafId() {
    var nodeId = MoveNode.rootId;

    while (true) {
      final childId = _mainChildId(nodeId);
      if (childId == null) return nodeId;
      nodeId = childId;
    }
  }

  String _uciFromSquares(int fromSquare, int toSquare, String san) {
    return '${Game.squareName(fromSquare)}${Game.squareName(toSquare)}'
        '${_promotionFromSan(san) ?? ''}';
  }

  String? _promotionFromSan(String san) {
    final match = RegExp(r'=([QRBN])').firstMatch(san);
    return match?.group(1)?.toLowerCase();
  }

  void _goToPreviousMove({bool fullMove = false}) {
    final step = fullMove ? 2 : 1;
    var targetId = _currentNodeId;

    for (var i = 0; i < step; i++) {
      final parentId = _moveTree[targetId]?.parentId;
      if (parentId == null) break;
      targetId = parentId;
    }

    _goToMoveNode(targetId);
  }

  void _goToNextMove({bool fullMove = false}) {
    final step = fullMove ? 2 : 1;
    var targetId = _currentNodeId;

    for (var i = 0; i < step; i++) {
      final childId = _mainChildId(targetId);
      if (childId == null) break;
      targetId = childId;
    }

    _goToMoveNode(targetId);
  }

  void _goToMoveNode(String nodeId) {
    final node = _moveTree[nodeId];
    if (node == null || nodeId == _currentNodeId) return;
    final pausesComputerSearch = _isComputerModeRunning &&
        _computerThinking &&
        _computerActiveNodeId != null &&
        nodeId != _computerActiveNodeId;

    setState(() {
      _clearPositionAnalysis();
      _clearHintInState();
      _clearReviewOverlayInState();
      if (pausesComputerSearch) {
        _computerRequestId++;
        _computerThinking = false;
        _computerMode = ComputerPlayMode.playing;
      }
      _currentNodeId = nodeId;
      _game = Game.fromFen(node.fenAfter);
      _selectedSquare = null;
      _legalTargets = [];
      _syncLastMoveHighlight();
    });
    if (pausesComputerSearch) {
      unawaited(_engineService.cancelCurrentSearch());
    }
    if (_computerMode != ComputerPlayMode.off) {
      _maybeStartComputerMove();
    } else {
      _reanalyzeIfEngineRunning();
    }
  }

  void _syncLastMoveHighlight() {
    final node = _currentMoveNode;
    if (node == null) {
      _lastMoveFrom = null;
      _lastMoveTo = null;
      return;
    }

    _lastMoveFrom = node.uci.length >= 4
        ? Game.squareIndex(node.uci.substring(0, 2))
        : null;
    _lastMoveTo = node.uci.length >= 4
        ? Game.squareIndex(node.uci.substring(2, 4))
        : null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearUserAnnotations();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPreviousMove(fullMove: isControlPressed);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToNextMove(fullMove: isControlPressed);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.home) {
      _goToMoveNode(MoveNode.rootId);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.end) {
      _goToMoveNode(_mainLineLeafId);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _startEngine() async {
    if (_computerMode != ComputerPlayMode.off) return;
    if (_engineRunning || _engineStarting) return;

    final controlRequestId = ++_engineControlRequestId;

    setState(() {
      _engineStarting = true;
      _engineError = null;
    });

    try {
      await _engineService.startEngine();
      if (!mounted || controlRequestId != _engineControlRequestId) return;

      setState(() {
        _engineRunning = true;
        _engineStarting = false;
      });
      _analyzeCurrentPosition();
    } catch (error) {
      debugPrint('engine error: $error');
      if (!mounted || controlRequestId != _engineControlRequestId) return;

      setState(() {
        _engineRunning = false;
        _engineStarting = false;
        _engineError = error.toString();
      });
    }
  }

  Future<void> _stopEngine() async {
    _engineControlRequestId++;

    setState(() {
      _engineRunning = false;
      _engineStarting = false;
      _isAnalyzing = false;
      _activeEngineSearchId = null;
      _activeEngineFen = null;
      _clearPositionAnalysis();
    });

    try {
      await _engineService.stopEngine();
    } catch (error) {
      debugPrint('engine error: $error');
      if (!mounted) return;

      setState(() {
        _engineError = error.toString();
      });
    }
  }

  void _reanalyzeIfEngineRunning() {
    if (!_engineRunning || _engineStarting) return;
    _analyzeCurrentPosition();
  }

  void _analyzeCurrentPosition() {
    if (!_engineRunning || _engineStarting) return;

    final fen = _game.fen;
    final searchId = _engineService.analyzeCurrentPosition(
      fen,
      depth: StockfishEngineService.defaultDepth,
      multiPv: StockfishEngineService.defaultMultiPv,
    );

    setState(() {
      _activeEngineSearchId = searchId;
      _activeEngineFen = fen;
      _isAnalyzing = true;
      _engineError = null;
      _engineResult = null;
      _bestMoveFrom = null;
      _bestMoveTo = null;
    });
  }

  void _handleEngineUpdate(EngineAnalysisResult result) {
    if (!mounted || !_engineRunning) return;
    if (_activeEngineSearchId != null &&
        result.searchId != _activeEngineSearchId) {
      return;
    }
    if (_activeEngineFen != null && result.fen != _activeEngineFen) {
      return;
    }

    final from = _uciMoveFrom(result.bestMoveUci);
    final to = _uciMoveTo(result.bestMoveUci);

    setState(() {
      _engineResult = result;
      _bestMoveFrom = from;
      _bestMoveTo = to;
      _engineError = null;
      _isAnalyzing = !result.isFinal;
    });
  }

  void _handleEngineStreamError(Object error) {
    debugPrint('engine error: $error');
    if (!mounted || !_engineRunning) return;

    setState(() {
      _engineError = error.toString();
      _engineResult = null;
      _bestMoveFrom = null;
      _bestMoveTo = null;
      _isAnalyzing = false;
    });
  }

  void _clearAnalysis() {
    unawaited(_engineService.cancelCurrentSearch());

    setState(() {
      _activeEngineSearchId = null;
      _activeEngineFen = null;
      _isAnalyzing = false;
      _clearPositionAnalysis();
    });
  }

  void _clearPositionAnalysis() {
    _isAnalyzing = false;
    _engineResult = null;
    _bestMoveFrom = null;
    _bestMoveTo = null;
    _engineError = null;
    _activeEngineSearchId = null;
    _activeEngineFen = null;
  }

  String? _uciMoveFrom(String bestMoveUci) {
    if (bestMoveUci.length < 4 || bestMoveUci == 'none') return null;

    final from = bestMoveUci.substring(0, 2);
    return Game.squareIndex(from) == null ? null : from;
  }

  String? _uciMoveTo(String bestMoveUci) {
    if (bestMoveUci.length < 4 || bestMoveUci == 'none') return null;

    final to = bestMoveUci.substring(2, 4);
    return Game.squareIndex(to) == null ? null : to;
  }

  void _flip() {
    setState(() {
      _flipped = !_flipped;
    });
  }

  void _toggleUserArrow(String fromSquare, String toSquare) {
    if (fromSquare == toSquare) {
      _toggleUserCircle(fromSquare);
      return;
    }

    setState(() {
      final existingIndex = _userArrows.indexWhere(
        (arrow) => arrow.matches(fromSquare, toSquare),
      );

      if (existingIndex >= 0) {
        _userArrows.removeAt(existingIndex);
      } else {
        _userArrows.add(
          BoardArrow(
            fromSquare: fromSquare,
            toSquare: toSquare,
          ),
        );
      }
    });
  }

  void _toggleUserCircle(String square) {
    setState(() {
      final existingIndex = _userCircles.indexWhere(
        (circle) => circle.matches(square),
      );

      if (existingIndex >= 0) {
        _userCircles.removeAt(existingIndex);
      } else {
        _userCircles.add(BoardCircle(square: square));
      }
    });
  }

  void _clearUserAnnotations({bool updateState = true}) {
    if (_userArrows.isEmpty && _userCircles.isEmpty) return;

    void clear() {
      _userArrows.clear();
      _userCircles.clear();
    }

    if (updateState) {
      setState(clear);
    } else {
      clear();
    }
  }

  void _setReviewOverlay(BoardReviewOverlay? overlay) {
    if (!mounted) return;

    setState(() {
      _reviewOverlay = overlay ?? const BoardReviewOverlay.empty();
    });
  }

  void _clearReviewOverlayInState() {
    _reviewOverlay = const BoardReviewOverlay.empty();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Training Board'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset Game',
              onPressed: _reset,
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 820;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _maxBoardWithEvaluationWidth(
                                constraints,
                              ),
                            ),
                            child: _buildBoardWithEvaluation(),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                        child: InfoPanel(
                          game: _game,
                          engineRunning: _engineRunning,
                          engineStarting: _engineStarting,
                          isEngineThinking: _isAnalyzing,
                          engineResult: _engineResult,
                          engineError: _engineError,
                          computerMode: _computerMode,
                          humanColor: _humanColor,
                          computerColor: _computerColor,
                          computerLevel: _computerLevel,
                          computerThinking: _computerThinking,
                          computerStatusText: _computerStatusText,
                          computerError: _computerError,
                          canRequestComputerHint: _canRequestComputerHint,
                          openingNameService: _openingNameService,
                          coachService: _coachService,
                          aiService: _aiService,
                          explorerRepository: _explorerRepository,
                          moveTree: _moveTree,
                          currentNodeId: _currentNodeId,
                          mainLineNodeIds: _mainLineNodeIds,
                          isAtMainLineEnd: _isAtMainLineEnd,
                          displayedSanMoveHistory: _displayedSanMoveHistory,
                          onExplorerMoveSelected: _onExplorerMoveSelected,
                          onMoveSelected: _goToMoveNode,
                          onUndo: _undo,
                          onReset: _reset,
                          onFlip: _flip,
                          onStartEngine: _startEngine,
                          onStopEngine: _stopEngine,
                          onClearAnalysis: _clearAnalysis,
                          onShowPlayComputerDialog: _showPlayComputerDialog,
                          onStopComputerGame: _stopComputerGame,
                          onRequestComputerHint: _requestComputerHint,
                          onReviewOverlayChanged: _setReviewOverlay,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildBoardWithEvaluation(),
                      const SizedBox(height: 16),
                      InfoPanel(
                        game: _game,
                        engineRunning: _engineRunning,
                        engineStarting: _engineStarting,
                        isEngineThinking: _isAnalyzing,
                        engineResult: _engineResult,
                        engineError: _engineError,
                        computerMode: _computerMode,
                        humanColor: _humanColor,
                        computerColor: _computerColor,
                        computerLevel: _computerLevel,
                        computerThinking: _computerThinking,
                        computerStatusText: _computerStatusText,
                        computerError: _computerError,
                        canRequestComputerHint: _canRequestComputerHint,
                        openingNameService: _openingNameService,
                        coachService: _coachService,
                        aiService: _aiService,
                        explorerRepository: _explorerRepository,
                        moveTree: _moveTree,
                        currentNodeId: _currentNodeId,
                        mainLineNodeIds: _mainLineNodeIds,
                        isAtMainLineEnd: _isAtMainLineEnd,
                        displayedSanMoveHistory: _displayedSanMoveHistory,
                        onExplorerMoveSelected: _onExplorerMoveSelected,
                        onMoveSelected: _goToMoveNode,
                        onUndo: _undo,
                        onReset: _reset,
                        onFlip: _flip,
                        onStartEngine: _startEngine,
                        onStopEngine: _stopEngine,
                        onClearAnalysis: _clearAnalysis,
                        onShowPlayComputerDialog: _showPlayComputerDialog,
                        onStopComputerGame: _stopComputerGame,
                        onRequestComputerHint: _requestComputerHint,
                        onReviewOverlayChanged: _setReviewOverlay,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return ChessBoardView(
      game: _game,
      flipped: _flipped,
      selectedSquare: _selectedSquare,
      legalTargets: _legalTargets,
      lastMoveFrom: _lastMoveFrom,
      lastMoveTo: _lastMoveTo,
      bestMoveFrom: _bestMoveFrom,
      bestMoveTo: _bestMoveTo,
      hintMoveFrom: _hintMoveFrom,
      hintMoveTo: _hintMoveTo,
      canMovePieces: _canUserMoveNow,
      checkedKingSquare: _game.checkedKingSquareName,
      isCheckmate: _game.isCheckmate,
      userArrows: _userArrows,
      userCircles: _userCircles,
      reviewOverlay: _reviewOverlay,
      onSquareTap: _onSquareTap,
      onPieceDropped: _onPieceDropped,
      onUserArrowDrawn: _toggleUserArrow,
      onUserCircleDrawn: _toggleUserCircle,
    );
  }

  Widget _buildBoardWithEvaluation() {
    const evaluationBarWidth = 42.0;
    const boardGap = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : availableWidth;
        final boardSize = math.max(
          0.0,
          math.min(
            availableWidth - evaluationBarWidth - boardGap,
            availableHeight,
          ),
        );

        return SizedBox(
          width: boardSize + evaluationBarWidth + boardGap,
          height: boardSize,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: evaluationBarWidth,
                child: EvaluationBar(
                  evaluationPawns: _engineResult?.evaluationPawns,
                  mateIn: _engineResult?.mateIn,
                  isAnalyzing: _isAnalyzing,
                ),
              ),
              const SizedBox(width: boardGap),
              SizedBox.square(
                dimension: boardSize,
                child: _buildBoard(),
              ),
            ],
          ),
        );
      },
    );
  }

  double _maxBoardWithEvaluationWidth(BoxConstraints constraints) {
    const sideUiWidth = 52.0;
    if (!constraints.maxHeight.isFinite) return constraints.maxWidth;
    return math.max(260.0, constraints.maxHeight - 40 + sideUiWidth);
  }
}
