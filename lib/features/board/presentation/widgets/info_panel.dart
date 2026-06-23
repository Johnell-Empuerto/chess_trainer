import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/core/chess/game.dart';
import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/engine/presentation/widgets/analysis_lines_panel.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/presentation/explorer_panel.dart';

enum _InfoPanelTab { analysis, explore }

class InfoPanel extends StatefulWidget {
  final Game game;
  final bool engineRunning;
  final bool engineStarting;
  final bool isEngineThinking;
  final EngineAnalysisResult? engineResult;
  final String? engineError;
  final OpeningExplorerRepository explorerRepository;
  final List<MoveRecord> moveHistory;
  final int currentMoveCursor;
  final bool isAtLatestMove;
  final List<String> displayedSanMoveHistory;
  final ValueChanged<ExplorerMoveStat> onExplorerMoveSelected;
  final ValueChanged<int> onMoveHistorySelected;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onFlip;
  final Future<void> Function() onStartEngine;
  final Future<void> Function() onStopEngine;
  final VoidCallback onClearAnalysis;

  const InfoPanel({
    super.key,
    required this.game,
    required this.engineRunning,
    required this.engineStarting,
    required this.isEngineThinking,
    required this.engineResult,
    required this.engineError,
    required this.explorerRepository,
    required this.moveHistory,
    required this.currentMoveCursor,
    required this.isAtLatestMove,
    required this.displayedSanMoveHistory,
    required this.onExplorerMoveSelected,
    required this.onMoveHistorySelected,
    required this.onUndo,
    required this.onReset,
    required this.onFlip,
    required this.onStartEngine,
    required this.onStopEngine,
    required this.onClearAnalysis,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  _InfoPanelTab _selectedTab = _InfoPanelTab.analysis;

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
                setState(() {
                  _selectedTab = tab;
                });
              },
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _selectedTab == _InfoPanelTab.analysis
                  ? _buildAnalysisTab()
                  : ExplorerPanel(
                      key: const ValueKey('explore-tab'),
                      currentFen: widget.game.fen,
                      sanMoveHistory: widget.displayedSanMoveHistory,
                      engineResult: widget.engineResult,
                      repository: widget.explorerRepository,
                      onMoveSelected: widget.onExplorerMoveSelected,
                    ),
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
        if (!widget.isAtLatestMove) ...[
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
        _MoveHistoryTable(
          moveHistory: widget.moveHistory,
          currentMoveCursor: widget.currentMoveCursor,
          onMoveSelected: widget.onMoveHistorySelected,
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
    final cursor = widget.currentMoveCursor;
    if (cursor == 0) {
      return 'Viewing starting position';
    }

    final move = widget.moveHistory[cursor - 1];
    final marker =
        move.isWhiteMove ? '${move.moveNumber}.' : '${move.moveNumber}...';
    return 'Viewing move $marker ${move.san}';
  }

  Widget _buildEngineSection() {
    final result = widget.engineResult;
    final error = widget.engineError;
    final hasAnalysis = result != null || error != null;

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
                  onPressed: widget.engineStarting
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

  String _engineStatusText() {
    if (widget.engineError != null) return 'Engine: Error';
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

class _MoveHistoryTable extends StatelessWidget {
  final List<MoveRecord> moveHistory;
  final int currentMoveCursor;
  final ValueChanged<int> onMoveSelected;

  const _MoveHistoryTable({
    required this.moveHistory,
    required this.currentMoveCursor,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _moveRows();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              'Main Line',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: rows.isEmpty
                ? const SizedBox(height: 8)
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      return _MoveHistoryRow(
                        row: rows[index],
                        currentMoveCursor: currentMoveCursor,
                        onMoveSelected: onMoveSelected,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_MoveHistoryRowData> _moveRows() {
    final rows = <_MoveHistoryRowData>[];

    for (var i = 0; i < moveHistory.length; i++) {
      final move = moveHistory[i];

      if (move.isWhiteMove || rows.isEmpty) {
        rows.add(
          _MoveHistoryRowData(
            moveNumber: move.moveNumber,
            whiteMove: move.isWhiteMove ? move : null,
            whiteCursor: move.isWhiteMove ? i + 1 : null,
            blackMove: move.isBlackMove ? move : null,
            blackCursor: move.isBlackMove ? i + 1 : null,
          ),
        );
        continue;
      }

      final lastRow = rows.removeLast();
      rows.add(
        lastRow.copyWith(
          blackMove: move,
          blackCursor: i + 1,
        ),
      );
    }

    return rows;
  }
}

class _MoveHistoryRow extends StatelessWidget {
  final _MoveHistoryRowData row;
  final int currentMoveCursor;
  final ValueChanged<int> onMoveSelected;

  const _MoveHistoryRow({
    required this.row,
    required this.currentMoveCursor,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final whiteCursor = row.whiteCursor;
    final blackCursor = row.blackCursor;
    final isActiveRow =
        currentMoveCursor == whiteCursor || currentMoveCursor == blackCursor;

    return ColoredBox(
      color: isActiveRow ? const Color(0x1434D399) : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${row.moveNumber}.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: row.whiteMove == null || whiteCursor == null
                  ? const SizedBox.shrink()
                  : _MoveHistoryCell(
                      move: row.whiteMove!,
                      cursor: whiteCursor,
                      isSelected: currentMoveCursor == whiteCursor,
                      onMoveSelected: onMoveSelected,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: row.blackMove == null || blackCursor == null
                  ? const SizedBox.shrink()
                  : _MoveHistoryCell(
                      move: row.blackMove!,
                      cursor: blackCursor,
                      isSelected: currentMoveCursor == blackCursor,
                      onMoveSelected: onMoveSelected,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveHistoryCell extends StatelessWidget {
  final MoveRecord move;
  final int cursor;
  final bool isSelected;
  final ValueChanged<int> onMoveSelected;

  const _MoveHistoryCell({
    required this.move,
    required this.cursor,
    required this.isSelected,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0x2434D399) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => onMoveSelected(cursor),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: _SanMoveText(
            san: move.san,
            isWhiteMove: move.isWhiteMove,
          ),
        ),
      ),
    );
  }
}

class _MoveHistoryRowData {
  final int moveNumber;
  final MoveRecord? whiteMove;
  final int? whiteCursor;
  final MoveRecord? blackMove;
  final int? blackCursor;

  const _MoveHistoryRowData({
    required this.moveNumber,
    required this.whiteMove,
    required this.whiteCursor,
    required this.blackMove,
    required this.blackCursor,
  });

  _MoveHistoryRowData copyWith({
    MoveRecord? blackMove,
    int? blackCursor,
  }) {
    return _MoveHistoryRowData(
      moveNumber: moveNumber,
      whiteMove: whiteMove,
      whiteCursor: whiteCursor,
      blackMove: blackMove ?? this.blackMove,
      blackCursor: blackCursor ?? this.blackCursor,
    );
  }
}

class _SanMoveText extends StatelessWidget {
  final String san;
  final bool isWhiteMove;

  const _SanMoveText({
    required this.san,
    required this.isWhiteMove,
  });

  @override
  Widget build(BuildContext context) {
    final pieceLetter = san.isEmpty ? null : san[0];
    final symbol = _pieceSymbol(pieceLetter, isWhiteMove);
    final text = symbol == null ? san : san.substring(1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (symbol != null) ...[
          Text(
            symbol,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String? _pieceSymbol(String? pieceLetter, bool isWhiteMove) {
    switch (pieceLetter) {
      case 'N':
        return isWhiteMove ? '\u2658' : '\u265E';
      case 'B':
        return isWhiteMove ? '\u2657' : '\u265D';
      case 'R':
        return isWhiteMove ? '\u2656' : '\u265C';
      case 'Q':
        return isWhiteMove ? '\u2655' : '\u265B';
      case 'K':
        return isWhiteMove ? '\u2654' : '\u265A';
      default:
        return null;
    }
  }
}
