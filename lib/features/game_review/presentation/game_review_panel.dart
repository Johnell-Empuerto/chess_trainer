import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';
import 'package:chess_trainer/features/game_review/data/game_review_service.dart';
import 'package:chess_trainer/features/game_review/domain/game_move_review.dart';
import 'package:chess_trainer/features/game_review/domain/game_review_report.dart';

class GameReviewPanel extends StatefulWidget {
  final Map<String, MoveNode> moveTree;
  final List<String> mainLineNodeIds;
  final GameReviewService reviewService;
  final String gameFingerprint;
  final String? currentNodeId;
  final String? openingName;
  final String? result;
  final int autoRunRequestId;
  final ValueChanged<String> onMoveSelected;
  final ValueChanged<GameMoveReview?>? onReviewMoveChanged;

  const GameReviewPanel({
    super.key,
    required this.moveTree,
    required this.mainLineNodeIds,
    required this.reviewService,
    required this.gameFingerprint,
    this.currentNodeId,
    this.openingName,
    this.result,
    this.autoRunRequestId = 0,
    required this.onMoveSelected,
    this.onReviewMoveChanged,
  });

  @override
  State<GameReviewPanel> createState() => _GameReviewPanelState();
}

class _GameReviewPanelState extends State<GameReviewPanel> {
  GameReviewReport? _report;
  bool _loading = false;
  String? _error;
  GameMoveReview? _selectedMove;
  final ScrollController _timelineScrollController = ScrollController();
  int _handledAutoRunRequestId = 0;

  @override
  void initState() {
    super.initState();
    _notifyReviewMove(null);
    _maybeAutoRunReview();
  }

  @override
  void didUpdateWidget(covariant GameReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.gameFingerprint != widget.gameFingerprint) {
      setState(() {
        _report = null;
        _loading = false;
        _error = null;
        _selectedMove = null;
      });
      _notifyReviewMove(null);
    }

    if (oldWidget.currentNodeId != widget.currentNodeId && _report != null) {
      _syncSelectedMoveWithCurrentNode();
    }

    _maybeAutoRunReview();
  }

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  Future<void> _runReview() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _report = null;
      _selectedMove = null;
    });
    _notifyReviewMove(null);

    try {
      final report = await widget.reviewService.reviewGame(
        moveTree: widget.moveTree,
        mainLineNodeIds: widget.mainLineNodeIds,
        openingName: widget.openingName,
        result: widget.result,
      );

      if (!mounted) return;

      if (report == null) {
        setState(() {
          _loading = false;
          _error = 'No moves to review. Play some moves first.';
        });
        _notifyReviewMove(null);
        return;
      }

      setState(() {
        _report = report;
        _selectedMove = _initialSelectedMove(report);
        _loading = false;
      });
      _notifyReviewMove(_selectedMove);
      _scrollTimelineToMove(_selectedMove);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      _notifyReviewMove(null);
    }
  }

  void _selectMove(GameMoveReview move) {
    setState(() => _selectedMove = move);
    _scrollTimelineToMove(move);
    widget.onMoveSelected(move.nodeId);
    _notifyReviewMove(move);
  }

  GameMoveReview? _initialSelectedMove(GameReviewReport report) {
    if (widget.currentNodeId == MoveNode.rootId) return null;

    return _moveForNode(report, widget.currentNodeId) ??
        (report.criticalMoments.isNotEmpty
            ? report.criticalMoments.first
            : report.moves.first);
  }

  GameMoveReview? _moveForNode(GameReviewReport report, String? nodeId) {
    if (nodeId == null) return null;

    for (final move in report.moves) {
      if (move.nodeId == nodeId) return move;
    }

    return null;
  }

  void _syncSelectedMoveWithCurrentNode() {
    final report = _report;
    if (report == null) return;

    final move = _moveForNode(report, widget.currentNodeId);
    if (move == null) {
      if (_selectedMove == null) return;
      setState(() {
        _selectedMove = null;
      });
      _notifyReviewMove(null);
      return;
    }
    if (move.nodeId == _selectedMove?.nodeId) return;

    setState(() {
      _selectedMove = move;
    });
    _scrollTimelineToMove(move);
    _notifyReviewMove(move);
  }

  void _scrollTimelineToMove(GameMoveReview? move) {
    if (move == null) return;

    final report = _report;
    if (report == null) return;

    final index = report.moves.indexWhere((item) => item.nodeId == move.nodeId);
    if (index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_timelineScrollController.hasClients) return;
      final targetOffset = (index * 60.0).clamp(
        0.0,
        _timelineScrollController.position.maxScrollExtent,
      );
      _timelineScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _notifyReviewMove(GameMoveReview? move) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReviewMoveChanged?.call(move);
    });
  }

  void _maybeAutoRunReview() {
    final requestId = widget.autoRunRequestId;
    if (requestId <= 0 || requestId == _handledAutoRunRequestId) return;
    _handledAutoRunRequestId = requestId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading) return;
      unawaited(_runReview());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('game-review-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_report == null && !_loading && _error == null)
          _buildStartPrompt()
        else if (_loading)
          _buildLoading()
        else if (_error != null)
          _buildError()
        else ...[
          _buildSummaryCard(),
          const SizedBox(height: 12),
          _buildMoveTimeline(),
          if (_selectedMove != null) ...[
            const SizedBox(height: 12),
            _buildSelectedMoveDetail(),
          ],
          if (_report!.criticalMoments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCriticalMoments(),
          ],
          if (_report!.coachSummary != null &&
              _report!.coachSummary!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCoachSummary(),
          ],
          if (_report!.trainingThemes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTrainingThemes(),
          ],
        ],
      ],
    );
  }

  Widget _buildStartPrompt() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.auto_awesome, size: 36, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            'Review your entire game move by move.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Stockfish will analyze every move and a coach summary will be generated.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _runReview,
            icon: const Icon(Icons.analytics),
            label: const Text('Run Full Game Review'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 12),
          Text(
            'Analyzing game, please wait\u2026',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent.shade200),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: Colors.redAccent.shade200,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _runReview,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final report = _report!;
    final totalEval =
        report.whiteStats.totalEvalLoss + report.blackStats.totalEvalLoss;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _accuracyBadge('White', report.whiteStats.accuracy,
                  report.whiteStats, report.result.contains('White')),
              const SizedBox(width: 12),
              _accuracyBadge('Black', report.blackStats.accuracy,
                  report.blackStats, report.result.contains('Black')),
            ],
          ),
          const SizedBox(height: 10),
          if (report.openingName != null && report.openingName!.isNotEmpty)
            _summaryRow('Opening', report.openingName!),
          _summaryRow('Total moves', '${report.totalMoves}'),
          _summaryRow(
              'Total eval loss', '${totalEval.toStringAsFixed(1)} pawns'),
          if (report.result.isNotEmpty) _summaryRow('Result', report.result),
        ],
      ),
    );
  }

  Widget _accuracyBadge(
      String side, double accuracy, PlayerStats stats, bool isWinner) {
    final color = accuracy >= 90
        ? const Color(0xFF34D399)
        : accuracy >= 75
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  side,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (isWinner) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.emoji_events, size: 14, color: color),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${accuracy.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${stats.blunderCount}B ${stats.mistakeCount}M ${stats.inaccuracyCount}I',
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveTimeline() {
    final moves = _report!.moves;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Move timeline',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 120,
          child: ListView.separated(
            controller: _timelineScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: moves.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final move = moves[index];
              final isSelected = _selectedMove?.nodeId == move.nodeId;
              final accentColor = _moveAccentColor(move);

              return GestureDetector(
                onTap: () => _selectMove(move),
                child: Container(
                  width: 56,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? accentColor.withAlpha(30) : AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? accentColor : AppTheme.divider,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${move.moveNumber}.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        move.playedSan,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        _moveIcon(move),
                        size: 12,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedMoveDetail() {
    final move = _selectedMove!;
    final best = move.bestMoveSan.isNotEmpty
        ? move.bestMoveSan
        : (move.bestMoveUci.isNotEmpty ? move.bestMoveUci : 'None');
    final accentColor = _moveAccentColor(move);

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
              Icon(_moveIcon(move), size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Move ${move.moveNumber} ${move.playedSan}',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _moveLabel(move),
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow('Played by', move.playedBy == 'white' ? 'White' : 'Black'),
          if (move.shouldShowDetailedInsight && best != 'None')
            _detailRow('Best move', best),
          if (move.evalBefore != null)
            _detailRow('Eval before', _formatEval(move.evalBefore!)),
          if (move.evalAfter != null)
            _detailRow('Eval after', _formatEval(move.evalAfter!)),
          if (move.mateDescription != null)
            _detailRow('Mate note', move.mateDescription!)
          else if (move.displayEvalLoss > 0.01 && !move.isBookMove)
            _detailRow(
              'Eval loss',
              '${move.displayEvalLoss.toStringAsFixed(2)} pawns',
            ),
          if (move.pvLine.isNotEmpty && move.shouldShowDetailedInsight)
            _detailRow('PV', move.pvLine.take(4).join(' ')),
          if (move.openingName != null && move.openingName!.isNotEmpty)
            _detailRow('Opening', move.openingName!),
          if (move.openingMoveNote != null)
            _detailRow('Opening note', move.openingMoveNote!),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _explanationForMove(move),
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriticalMoments() {
    final moments = _report!.criticalMoments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 16, color: const Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text(
              'Critical moments',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...moments.map((m) {
          final accentColor = _moveAccentColor(m);
          return GestureDetector(
            onTap: () => _selectMove(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  Icon(_moveIcon(m), size: 14, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    '${m.moveNumber}. ${m.playedSan}',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '${_moveLabel(m)} (${_criticalLossText(m)})',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.textSecondary),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCoachSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8B5CF6).withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 16, color: const Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              Text(
                'Coach summary',
                style: TextStyle(
                  color: const Color(0xFF8B5CF6),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _report!.coachSummary!,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingThemes() {
    final themes = _report!.trainingThemes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline,
                size: 16, color: const Color(0xFF34D399)),
            const SizedBox(width: 6),
            Text(
              'Training themes',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: themes.map((theme) {
            final descriptions = {
              'Tactical awareness':
                  'Train pattern recognition with tactics puzzles.',
              'Endgame technique':
                  'Study basic endgame principles and king activation.',
              'Opening principles':
                  'Develop pieces, control center, castle early.',
              'King safety': 'Castle early and keep king shelter intact.',
              'Center control': 'Fight for central squares e4-d4-e5-d5.',
              'Piece development': 'Bring all pieces out before attacking.',
              'Material awareness':
                  'Count attackers and defenders before each trade.',
              'Pawn structure':
                  'Avoid doubled/isolated pawns without compensation.',
              'Prophylactic thinking':
                  'Anticipate opponent threats before they happen.',
              'Tempo and initiative': 'Make forcing moves that demand replies.',
              'Initiative and attack':
                  'Keep pressure on; active play beats passive.',
              'Piece coordination':
                  'Make pieces support each other, not scattered.',
            };

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: const Color(0xFF34D399)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          theme,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descriptions[theme] ?? '',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatEval(double eval) {
    final sign = eval > 0 ? '+' : '';
    return '$sign${eval.toStringAsFixed(2)}';
  }

  Color _moveAccentColor(GameMoveReview move) {
    if (move.isBookMove) return const Color(0xFF5BC0EB);
    return move.quality.color;
  }

  String _moveLabel(GameMoveReview move) {
    if (move.isBookMove) return 'Book';
    return move.quality.label;
  }

  IconData _moveIcon(GameMoveReview move) {
    if (move.isBookMove) return Icons.menu_book;
    return _qualityIcon(move.quality);
  }

  String _criticalLossText(GameMoveReview move) {
    if (move.isCheckmateMove || move.quality == MoveQuality.checkmate) {
      return 'delivers checkmate';
    }
    if (move.mateDescription != null && move.mateDescription!.isNotEmpty) {
      return move.mateDescription!;
    }

    return '${move.displayEvalLoss.toStringAsFixed(1)} pawns';
  }

  IconData _qualityIcon(MoveQuality quality) {
    switch (quality) {
      case MoveQuality.checkmate:
        return Icons.emoji_events;
      case MoveQuality.brilliant:
        return Icons.star;
      case MoveQuality.excellent:
        return Icons.check_circle;
      case MoveQuality.good:
        return Icons.remove_circle_outline;
      case MoveQuality.inaccuracy:
        return Icons.warning_amber_rounded;
      case MoveQuality.mistake:
        return Icons.error_outline;
      case MoveQuality.blunder:
        return Icons.report;
    }
  }

  String _explanationForMove(GameMoveReview move) {
    if (move.isCheckmateMove) return _checkmateExplanation(move);

    if (!move.shouldShowDetailedInsight) {
      return _compactExplanationForMove(move);
    }

    if (move.bestMoveSan.isEmpty && move.bestMoveUci.isEmpty) {
      return _templateByQuality(move);
    }

    final best =
        move.bestMoveSan.isNotEmpty ? move.bestMoveSan : move.bestMoveUci;

    switch (move.quality) {
      case MoveQuality.checkmate:
        return _checkmateExplanation(move);
      case MoveQuality.brilliant:
        if (move.mateDescription != null) {
          return '${move.playedSan} is brilliant because it ${move.mateDescription}. Lesson: when the position is forcing, start with checks, captures, and direct threats.';
        }
        return '${move.playedSan} is a brilliant move! It finds the strongest idea available. The engine confirms this is the best continuation, giving you a clear advantage.';
      case MoveQuality.excellent:
        return '${move.playedSan} is an excellent move. It follows the engine\'s recommendation and improves your position without creating weaknesses.';
      case MoveQuality.good:
        return _compactExplanationForMove(move);
      case MoveQuality.inaccuracy:
        return 'What went wrong: ${move.playedSan} was playable but slightly imprecise. Better move: $best. Lesson: compare your candidate move with the opponent\'s most forcing reply before choosing. ${_lossSentence(move)}';
      case MoveQuality.mistake:
        return 'What went wrong: ${move.playedSan} gives the opponent a clearer chance to improve. Better move: $best. Lesson: before attacking or capturing, check whether your piece can be challenged with tempo. ${_lossSentence(move)}';
      case MoveQuality.blunder:
        if (move.mateDescription != null) {
          return 'What went wrong: ${move.playedSan} ${move.mateDescription}. Better move: $best. Lesson: in sharp positions, check forcing moves for both sides before playing a natural-looking move.';
        }
        return 'What went wrong: ${move.playedSan} changes the game sharply in your opponent\'s favor. Better move: $best. Lesson: look for loose pieces, direct tactics, and king-safety problems before moving. ${_lossSentence(move)}';
    }
  }

  String _checkmateExplanation(GameMoveReview move) {
    return '${move.playedSan} is the winning move. It ends the game immediately by checkmate, so there is no better continuation. Lesson: always look for forcing moves - checks, captures, and threats - especially near the enemy king.';
  }

  String _compactExplanationForMove(GameMoveReview move) {
    if (move.isBookMove) {
      return move.openingMoveNote ??
          'This is playable opening theory, even if Stockfish slightly prefers another move.';
    }

    if (move.quality == MoveQuality.good) {
      return 'This move keeps the position stable.';
    }

    return _templateByQuality(move);
  }

  String _lossSentence(GameMoveReview move) {
    if (move.mateDescription != null && move.mateDescription!.isNotEmpty) {
      return 'This is best understood as a ${move.mateDescription}, not as a normal pawn-loss number.';
    }

    return 'Evaluation loss: ${move.displayEvalLoss.toStringAsFixed(1)} pawns.';
  }

  String _templateByQuality(GameMoveReview move) {
    switch (move.quality) {
      case MoveQuality.checkmate:
        return 'This move ends the game by checkmate.';
      case MoveQuality.brilliant:
        return 'This move finds the strongest idea in the position.';
      case MoveQuality.excellent:
        return 'This move keeps your position healthy and follows good chess principles.';
      case MoveQuality.good:
        return 'A solid move that maintains the balance.';
      case MoveQuality.inaccuracy:
        return 'This move is not the most accurate. Try to find stronger continuations.';
      case MoveQuality.mistake:
        return 'This move creates problems. Look for better alternatives before committing.';
      case MoveQuality.blunder:
        return 'This move significantly worsens your position. Take more time to check candidate moves.';
    }
  }
}
