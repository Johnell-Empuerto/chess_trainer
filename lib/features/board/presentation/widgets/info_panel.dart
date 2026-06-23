import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/core/chess/game.dart';
import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/board/domain/board_annotation.dart';
import 'package:chess_trainer/features/board/presentation/widgets/move_tree_notation.dart';
import 'package:chess_trainer/features/coach/data/ai_explainer_service.dart';
import 'package:chess_trainer/features/coach/data/stockfish_coach_service.dart';
import 'package:chess_trainer/features/coach/domain/coach_move_review.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';
import 'package:chess_trainer/features/coach/presentation/coach_panel.dart';
import 'package:chess_trainer/features/computer/domain/computer_level.dart';
import 'package:chess_trainer/features/computer/domain/computer_play_mode.dart';
import 'package:chess_trainer/features/computer/presentation/computer_game_card.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/engine/presentation/widgets/analysis_lines_panel.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/data/opening_name_service.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/domain/opening_name.dart';
import 'package:chess_trainer/features/explorer/presentation/explorer_panel.dart';
import 'package:chess_trainer/features/game_review/data/game_review_service.dart';
import 'package:chess_trainer/features/game_review/domain/game_move_review.dart';
import 'package:chess_trainer/features/game_review/presentation/game_review_panel.dart';

enum _InfoPanelTab { analysis, explore, review, gameReview }

class InfoPanel extends StatefulWidget {
  final Game game;
  final bool engineRunning;
  final bool engineStarting;
  final bool isEngineThinking;
  final EngineAnalysisResult? engineResult;
  final String? engineError;
  final ComputerPlayMode computerMode;
  final String? humanColor;
  final String? computerColor;
  final ComputerLevel computerLevel;
  final bool computerThinking;
  final String computerStatusText;
  final String? computerError;
  final bool canRequestComputerHint;
  final OpeningExplorerRepository explorerRepository;
  final OpeningNameService openingNameService;
  final StockfishCoachService coachService;
  final AiExplainerService? aiService;
  final Map<String, MoveNode> moveTree;
  final String currentNodeId;
  final List<String> mainLineNodeIds;
  final bool isAtMainLineEnd;
  final List<String> displayedSanMoveHistory;
  final String? importedGameResult;
  final String? importedOpeningName;
  final ValueChanged<ExplorerMoveStat> onExplorerMoveSelected;
  final ValueChanged<String> onMoveSelected;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onFlip;
  final Future<void> Function() onStartEngine;
  final Future<void> Function() onStopEngine;
  final VoidCallback onClearAnalysis;
  final VoidCallback onShowPlayComputerDialog;
  final VoidCallback onStopComputerGame;
  final VoidCallback onRequestComputerHint;
  final ValueChanged<BoardReviewOverlay?> onReviewOverlayChanged;
  final int showGameReviewRequestId;
  final int autoGameReviewRequestId;

  const InfoPanel({
    super.key,
    required this.game,
    required this.engineRunning,
    required this.engineStarting,
    required this.isEngineThinking,
    required this.engineResult,
    required this.engineError,
    required this.computerMode,
    required this.humanColor,
    required this.computerColor,
    required this.computerLevel,
    required this.computerThinking,
    required this.computerStatusText,
    required this.computerError,
    required this.canRequestComputerHint,
    required this.explorerRepository,
    required this.openingNameService,
    required this.coachService,
    this.aiService,
    required this.moveTree,
    required this.currentNodeId,
    required this.mainLineNodeIds,
    required this.isAtMainLineEnd,
    required this.displayedSanMoveHistory,
    this.importedGameResult,
    this.importedOpeningName,
    required this.onExplorerMoveSelected,
    required this.onMoveSelected,
    required this.onUndo,
    required this.onReset,
    required this.onFlip,
    required this.onStartEngine,
    required this.onStopEngine,
    required this.onClearAnalysis,
    required this.onShowPlayComputerDialog,
    required this.onStopComputerGame,
    required this.onRequestComputerHint,
    required this.onReviewOverlayChanged,
    required this.showGameReviewRequestId,
    required this.autoGameReviewRequestId,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  _InfoPanelTab _selectedTab = _InfoPanelTab.analysis;
  late final GameReviewService _gameReviewService = GameReviewService(
    coachService: widget.coachService,
    aiService: widget.aiService,
  );

  @override
  void didUpdateWidget(covariant InfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldOpenGameReview =
        oldWidget.showGameReviewRequestId != widget.showGameReviewRequestId ||
            oldWidget.autoGameReviewRequestId != widget.autoGameReviewRequestId;

    if (shouldOpenGameReview && _selectedTab != _InfoPanelTab.gameReview) {
      setState(() {
        _selectedTab = _InfoPanelTab.gameReview;
      });
      _notifyReviewOverlay(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _PanelTabs(
              selectedTab: _selectedTab,
              onSelected: (tab) {
                if (tab == _selectedTab) return;
                setState(() {
                  _selectedTab = tab;
                });
                _notifyReviewOverlay(null);
              },
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_selectedTab) {
                _InfoPanelTab.analysis => _buildAnalysisTab(),
                _InfoPanelTab.explore => ExplorerPanel(
                    key: const ValueKey('explore-tab'),
                    currentFen: widget.game.fen,
                    sanMoveHistory: widget.displayedSanMoveHistory,
                    engineResult: widget.engineResult,
                    repository: widget.explorerRepository,
                    onMoveSelected: widget.onExplorerMoveSelected,
                  ),
                _InfoPanelTab.review => _buildReviewTab(),
                _InfoPanelTab.gameReview => _buildGameReviewTab(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Turn: ${widget.game.turn.displayName}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Move: ${widget.game.moveNumber}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (!widget.isAtMainLineEnd) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x2434D399),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x5534D399)),
            ),
            child: Text(
              _cursorStatusText(),
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnalysisTab() {
    return Column(
      key: const ValueKey('analysis-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isEngineThinking || widget.engineStarting) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        _buildEngineSection(),
        const SizedBox(height: 12),
        if (widget.computerMode == ComputerPlayMode.off)
          ElevatedButton.icon(
            onPressed: widget.onShowPlayComputerDialog,
            icon: const Icon(Icons.smart_toy_outlined),
            label: const Text('Play vs Computer'),
          )
        else
          ComputerGameCard(
            mode: widget.computerMode,
            humanColor: widget.humanColor,
            computerColor: widget.computerColor,
            level: widget.computerLevel,
            computerThinking: widget.computerThinking,
            canRequestHint: widget.canRequestComputerHint,
            statusText: widget.computerStatusText,
            error: widget.computerError,
            onStopGame: widget.onStopComputerGame,
            onRequestHint: widget.onRequestComputerHint,
          ),
        if (widget.game.inCheck ||
            widget.game.isCheckmate ||
            widget.game.isStalemate) ...[
          const SizedBox(height: 10),
          Text(
            _statusText(),
            style: TextStyle(
              color:
                  widget.game.isCheckmate ? Colors.redAccent : AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        MoveTreeNotation(
          moveTree: widget.moveTree,
          mainLineNodeIds: widget.mainLineNodeIds,
          currentNodeId: widget.currentNodeId,
          onMoveSelected: widget.onMoveSelected,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onUndo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onFlip,
                icon: const Icon(Icons.rotate_90_degrees_cw),
                label: const Text('Flip'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _statusText() {
    if (widget.game.isCheckmate) return 'Checkmate';
    if (widget.game.isStalemate) return 'Stalemate';
    if (widget.game.inCheck) {
      return '${widget.game.turn.displayName} is in check';
    }
    return '';
  }

  String _cursorStatusText() {
    final node = widget.moveTree[widget.currentNodeId];
    if (node == null || node.isRoot) {
      return 'Viewing starting position';
    }

    final marker =
        node.isWhiteMove ? '${node.moveNumber}.' : '${node.moveNumber}...';
    return 'Viewing move $marker ${node.san}';
  }

  Widget _buildEngineSection() {
    final result = widget.engineResult;
    final error = widget.engineError;
    final hasAnalysis = result != null || error != null;
    final computerModeActive = widget.computerMode != ComputerPlayMode.off;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.engineStarting || computerModeActive
                      ? null
                      : () {
                          if (widget.engineRunning) {
                            widget.onStopEngine();
                          } else {
                            widget.onStartEngine();
                          }
                        },
                  icon: Icon(
                    widget.engineRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                    widget.engineRunning ? 'Stop Engine' : 'Start Engine',
                  ),
                ),
              ),
              if (hasAnalysis || widget.isEngineThinking) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear Analysis',
                  onPressed: widget.onClearAnalysis,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _engineStatusText(),
            style: TextStyle(
              color: error != null ? Colors.redAccent : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(
              error,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (result != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EngineResultDetails(result: result),
                const SizedBox(height: 10),
                AnalysisLinesPanel(
                  result: result,
                  isAnalyzing: widget.isEngineThinking,
                ),
              ],
            )
          else if (widget.engineRunning && widget.isEngineThinking)
            AnalysisLinesPanel(
              result: null,
              isAnalyzing: widget.isEngineThinking,
            )
          else
            Text(
              widget.engineRunning
                  ? 'Engine is ready and will update after each legal move.'
                  : computerModeActive
                      ? 'Engine analysis can be started after stopping the computer game.'
                      : 'Start Engine to get a Stockfish suggestion.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          if (hasAnalysis) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onClearAnalysis,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Arrow'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewTab() {
    final node = widget.moveTree[widget.currentNodeId];
    final isNonRootNode = node != null && !node.isRoot;

    return Column(
      key: const ValueKey('review-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isNonRootNode)
          CoachPanel(
            moveNode: node,
            coachService: widget.coachService,
            aiService: widget.aiService,
            openingName: _resolveOpeningName(node),
            onReviewChanged: (review) {
              _notifyReviewOverlay(_overlayForCoachReview(review));
            },
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Select a played move from the move tree to review.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGameReviewTab() {
    return FutureBuilder<OpeningName?>(
      future: widget.openingNameService.matchOpening(
        currentFen: widget.game.fen,
        sanMoveHistory: widget.displayedSanMoveHistory,
      ),
      builder: (context, snapshot) {
        final openingName =
            snapshot.data?.displayName ?? widget.importedOpeningName;
        return GameReviewPanel(
          key: const ValueKey('game-review-tab'),
          moveTree: widget.moveTree,
          mainLineNodeIds: widget.mainLineNodeIds,
          reviewService: _gameReviewService,
          gameFingerprint: _gameReviewFingerprint(),
          currentNodeId: widget.currentNodeId,
          openingName: openingName,
          result: _gameResultText(),
          autoRunRequestId: widget.autoGameReviewRequestId,
          onMoveSelected: widget.onMoveSelected,
          onReviewMoveChanged: (move) {
            _notifyReviewOverlay(_overlayForGameMove(move));
          },
        );
      },
    );
  }

  String _gameReviewFingerprint() {
    return widget.mainLineNodeIds
        .map((nodeId) => widget.moveTree[nodeId]?.fenAfter ?? nodeId)
        .join('|');
  }

  void _notifyReviewOverlay(BoardReviewOverlay? overlay) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReviewOverlayChanged(overlay);
    });
  }

  BoardReviewOverlay? _overlayForCoachReview(CoachMoveReview? review) {
    if (review == null || review.hasError) return null;

    return _overlayForReviewedMove(
      playedUci: review.playedUci,
      bestMoveUci: review.bestMoveUci,
      quality: review.quality,
      isBookMove: false,
      isCheckmateMove: review.isCheckmateMove,
    );
  }

  BoardReviewOverlay? _overlayForGameMove(GameMoveReview? move) {
    if (move == null) return null;

    return _overlayForReviewedMove(
      playedUci: _playedUciForMove(move),
      bestMoveUci: move.bestMoveUci,
      quality: move.quality,
      isBookMove: move.isBookMove,
      isCheckmateMove: move.isCheckmateMove,
    );
  }

  String _playedUciForMove(GameMoveReview move) {
    final node = widget.moveTree[move.nodeId];
    return node?.uci ?? '';
  }

  BoardReviewOverlay? _overlayForReviewedMove({
    required String playedUci,
    required String bestMoveUci,
    required MoveQuality quality,
    required bool isBookMove,
    required bool isCheckmateMove,
  }) {
    if (isBookMove || quality == MoveQuality.good) return null;

    final playedSquares = _uciSquares(playedUci);
    if (playedSquares == null) return null;

    final annotationType = _annotationTypeForMove(
      quality: quality,
      isCheckmateMove: isCheckmateMove,
    );
    if (annotationType == null) return null;

    final arrows = <ReviewArrow>[
      ReviewArrow(
        fromSquare: playedSquares.$1,
        toSquare: playedSquares.$2,
        type: annotationType,
      ),
    ];
    final badges = <ReviewBadge>[
      ReviewBadge(
        square: playedSquares.$2,
        label: _badgeLabelForMove(
          quality: quality,
          isCheckmateMove: isCheckmateMove,
        ),
        type: annotationType,
      ),
    ];

    if (_shouldShowSuggestion(quality, isCheckmateMove)) {
      final bestSquares = _uciSquares(bestMoveUci);
      if (bestSquares != null &&
          (bestSquares.$1 != playedSquares.$1 ||
              bestSquares.$2 != playedSquares.$2)) {
        arrows.add(
          ReviewArrow(
            fromSquare: bestSquares.$1,
            toSquare: bestSquares.$2,
            type: ReviewAnnotationType.suggestion,
            isSuggestion: true,
          ),
        );
      }
    }

    return BoardReviewOverlay(arrows: arrows, badges: badges);
  }

  (String, String)? _uciSquares(String uci) {
    if (uci.length < 4 || uci == 'none') return null;

    final from = uci.substring(0, 2).toLowerCase();
    final to = uci.substring(2, 4).toLowerCase();
    if (!_isSquareName(from) || !_isSquareName(to)) return null;
    return (from, to);
  }

  bool _isSquareName(String square) {
    if (square.length != 2) return false;
    final file = square.codeUnitAt(0);
    final rank = square.codeUnitAt(1);
    return file >= 'a'.codeUnitAt(0) &&
        file <= 'h'.codeUnitAt(0) &&
        rank >= '1'.codeUnitAt(0) &&
        rank <= '8'.codeUnitAt(0);
  }

  ReviewAnnotationType? _annotationTypeForMove({
    required MoveQuality quality,
    required bool isCheckmateMove,
  }) {
    if (isCheckmateMove) {
      return ReviewAnnotationType.checkmate;
    }

    switch (quality) {
      case MoveQuality.checkmate:
        return ReviewAnnotationType.checkmate;
      case MoveQuality.brilliant:
        return ReviewAnnotationType.brilliant;
      case MoveQuality.excellent:
        return ReviewAnnotationType.good;
      case MoveQuality.inaccuracy:
        return ReviewAnnotationType.inaccuracy;
      case MoveQuality.mistake:
        return ReviewAnnotationType.mistake;
      case MoveQuality.blunder:
        return ReviewAnnotationType.blunder;
      case MoveQuality.good:
        return null;
    }
  }

  String _badgeLabelForMove({
    required MoveQuality quality,
    required bool isCheckmateMove,
  }) {
    if (isCheckmateMove) return '#';

    switch (quality) {
      case MoveQuality.checkmate:
        return '#';
      case MoveQuality.brilliant:
        return '!!';
      case MoveQuality.excellent:
        return '!';
      case MoveQuality.inaccuracy:
        return '?!';
      case MoveQuality.mistake:
        return '?';
      case MoveQuality.blunder:
        return '??';
      case MoveQuality.good:
        return '';
    }
  }

  bool _shouldShowSuggestion(MoveQuality quality, bool isCheckmateMove) {
    if (isCheckmateMove || quality == MoveQuality.checkmate) return false;
    return quality == MoveQuality.blunder ||
        quality == MoveQuality.mistake ||
        quality == MoveQuality.inaccuracy;
  }

  String _gameResultText() {
    if (widget.game.isCheckmate) {
      final winner = widget.game.turn == Turn.white ? 'Black' : 'White';
      return '$winner wins by checkmate';
    }
    if (widget.game.isStalemate) return 'Draw by stalemate';
    return widget.importedGameResult ?? '';
  }

  String? _resolveOpeningName(MoveNode node) {
    try {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _engineStatusText() {
    if (widget.engineError != null) return 'Engine: Error';
    if (widget.computerMode != ComputerPlayMode.off) {
      return 'Engine: Reserved for computer game';
    }
    if (widget.engineStarting) return 'Engine: Starting...';
    if (widget.isEngineThinking) return 'Engine: Analyzing...';
    if (widget.engineRunning) return 'Engine: Running';
    return 'Engine: Off';
  }
}

class _PanelTabs extends StatelessWidget {
  final _InfoPanelTab selectedTab;
  final ValueChanged<_InfoPanelTab> onSelected;

  const _PanelTabs({
    required this.selectedTab,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PanelTabButton(
              icon: Icons.analytics,
              label: 'Analysis',
              selected: selectedTab == _InfoPanelTab.analysis,
              onTap: () => onSelected(_InfoPanelTab.analysis),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PanelTabButton(
              icon: Icons.travel_explore,
              label: 'Explore',
              selected: selectedTab == _InfoPanelTab.explore,
              onTap: () => onSelected(_InfoPanelTab.explore),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PanelTabButton(
              icon: Icons.school,
              label: 'Review',
              selected: selectedTab == _InfoPanelTab.review,
              onTap: () => onSelected(_InfoPanelTab.review),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PanelTabButton(
              icon: Icons.assignment,
              label: 'Game',
              selected: selectedTab == _InfoPanelTab.gameReview,
              onTap: () => onSelected(_InfoPanelTab.gameReview),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PanelTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x2434D399) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color:
                    selected ? const Color(0xFF34D399) : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF34D399)
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineResultDetails extends StatelessWidget {
  final EngineAnalysisResult result;

  const _EngineResultDetails({required this.result});

  @override
  Widget build(BuildContext context) {
    final evaluation = result.evaluationPawns;
    final mateIn = result.mateIn;
    final pv = result.principalVariation.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EngineDetailRow(
          label: 'Best move',
          value: result.bestMoveUci,
        ),
        if (evaluation != null)
          _EngineDetailRow(
            label: 'Evaluation',
            value: _formatEvaluation(evaluation),
          ),
        if (mateIn != null)
          _EngineDetailRow(
            label: 'Mate',
            value: _formatMate(mateIn),
          ),
        _EngineDetailRow(
          label: 'Depth',
          value: '${result.depth}',
        ),
        if (pv.isNotEmpty)
          _EngineDetailRow(
            label: 'PV',
            value: pv,
          ),
      ],
    );
  }

  String _formatEvaluation(double evaluation) {
    final sign = evaluation > 0 ? '+' : '';
    return '$sign${evaluation.toStringAsFixed(2)}';
  }

  String _formatMate(int mateIn) {
    if (mateIn > 0) return 'M$mateIn';
    if (mateIn < 0) return '-M${mateIn.abs()}';
    return 'M0';
  }
}

class _EngineDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _EngineDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
