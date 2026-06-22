import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:chess_trainer/core/chess/game.dart';
import 'package:chess_trainer/features/board/presentation/widgets/chess_board_view.dart';
import 'package:chess_trainer/features/board/presentation/widgets/info_panel.dart';
import 'package:chess_trainer/features/engine/data/stockfish_engine_service.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/engine/presentation/widgets/evaluation_bar.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';

/// Interactive chess board screen.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late Game _game;
  final StockfishEngineService _engineService = StockfishEngineService();
  final OpeningExplorerRepository _explorerRepository =
      OpeningExplorerRepository();
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
  StreamSubscription<EngineAnalysisResult>? _engineSubscription;
  int? _activeEngineSearchId;
  String? _activeEngineFen;
  int _engineControlRequestId = 0;

  @override
  void initState() {
    super.initState();
    _game = Game.initial();
    _engineSubscription = _engineService.analysisStream.listen(
      _handleEngineUpdate,
      onError: _handleEngineStreamError,
    );
  }

  @override
  void dispose() {
    unawaited(_engineSubscription?.cancel());
    _engineService.dispose();
    _explorerRepository.dispose();
    super.dispose();
  }

  void _onSquareTap(int square) {
    final piece = _game.board[square];

    if (_selectedSquare != null) {
      if (_legalTargets.contains(square)) {
        final fromSquare = _selectedSquare!;
        final san = _game.playFromTo(_selectedSquare!, square);
        _debugMoveResult(fromSquare, square, san);

        if (san != null) {
          setState(() {
            _clearPositionAnalysis();
            _lastMoveFrom = fromSquare;
            _lastMoveTo = square;
            _selectedSquare = null;
            _legalTargets = [];
          });
          _reanalyzeIfEngineRunning();
        }

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

      debugPrint(
        'Move result fail: ${Game.squareName(_selectedSquare!)} to '
        '${Game.squareName(square)}',
      );
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
    final legalMoves = _game.legalMovesFrom(fromSquare);

    debugPrint('Drag drop fromSquare: ${Game.squareName(fromSquare)}');
    debugPrint('Drag drop toSquare: ${Game.squareName(toSquare)}');
    debugPrint(
      'Drag drop legal moves: ${legalMoves.map(Game.squareName).join(', ')}',
    );

    final san = _game.playFromTo(fromSquare, toSquare);
    _debugMoveResult(fromSquare, toSquare, san);

    if (san != null) {
      setState(() {
        _clearPositionAnalysis();
        _lastMoveFrom = fromSquare;
        _lastMoveTo = toSquare;
        _selectedSquare = null;
        _legalTargets = [];
      });
      _reanalyzeIfEngineRunning();
    }
  }

  void _debugSelection(int square, List<int> legalMoves) {
    debugPrint('Selected square: ${Game.squareName(square)}');
    debugPrint(
      'Legal moves from ${Game.squareName(square)}: '
      '${legalMoves.map(Game.squareName).join(', ')}',
    );
  }

  void _debugMoveResult(int fromSquare, int toSquare, String? san) {
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

  void _onExplorerMoveSelected(ExplorerMoveStat moveStat) {
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

    final san = _game.playUci(moveStat.moveUci);
    _debugMoveResult(fromSquare, toSquare, san);

    if (san != null) {
      setState(() {
        _clearPositionAnalysis();
        _lastMoveFrom = fromSquare;
        _lastMoveTo = toSquare;
        _selectedSquare = null;
        _legalTargets = [];
      });
      _reanalyzeIfEngineRunning();
    }
  }

  void _undo() {
    if (!_game.canUndo) return;

    setState(() {
      _clearPositionAnalysis();
      _game.undoMove();
      _selectedSquare = null;
      _legalTargets = [];
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
    _reanalyzeIfEngineRunning();
  }

  void _reset() {
    setState(() {
      _clearPositionAnalysis();
      _game = Game.initial();
      _selectedSquare = null;
      _legalTargets = [];
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
    _reanalyzeIfEngineRunning();
  }

  Future<void> _startEngine() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        explorerRepository: _explorerRepository,
                        onExplorerMoveSelected: _onExplorerMoveSelected,
                        onUndo: _undo,
                        onReset: _reset,
                        onFlip: _flip,
                        onStartEngine: _startEngine,
                        onStopEngine: _stopEngine,
                        onClearAnalysis: _clearAnalysis,
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
                      explorerRepository: _explorerRepository,
                      onExplorerMoveSelected: _onExplorerMoveSelected,
                      onUndo: _undo,
                      onReset: _reset,
                      onFlip: _flip,
                      onStartEngine: _startEngine,
                      onStopEngine: _stopEngine,
                      onClearAnalysis: _clearAnalysis,
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
      checkedKingSquare: _game.checkedKingSquareName,
      isCheckmate: _game.isCheckmate,
      onSquareTap: _onSquareTap,
      onPieceDropped: _onPieceDropped,
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
