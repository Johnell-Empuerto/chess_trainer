import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/explorer/data/game_database_import_service.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/presentation/explorer_move_table.dart';

class ExplorerPanel extends StatefulWidget {
  final String currentFen;
  final EngineAnalysisResult? engineResult;
  final OpeningExplorerRepository repository;
  final ValueChanged<ExplorerMoveStat> onMoveSelected;

  const ExplorerPanel({
    super.key,
    required this.currentFen,
    required this.engineResult,
    required this.repository,
    required this.onMoveSelected,
  });

  @override
  State<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends State<ExplorerPanel> {
  ExplorerImportStatus? _status;
  List<ExplorerMoveStat> _moves = const [];
  GameDatabaseImportSession? _importSession;
  StreamSubscription<ExplorerImportStatus>? _importSubscription;
  bool _loadingStatus = true;
  bool _loadingMoves = false;
  int _totalPositionGames = 0;
  int _queryRequestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatusAndMoves());
  }

  @override
  void didUpdateWidget(covariant ExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentFen != widget.currentFen &&
        _status?.isImported == true) {
      unawaited(_loadMoves());
    }
  }

  @override
  void dispose() {
    unawaited(_importSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    if (_loadingStatus && status == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DatabaseStatusCard(
          status: status,
          loadingStatus: _loadingStatus,
          onImport: _startImport,
          onCancel: _cancelImport,
          onRefresh: _loadStatusAndMoves,
        ),
        const SizedBox(height: 12),
        if (status?.isImported == true)
          _buildExplorerContent()
        else
          _buildNotImportedMessage(status),
      ],
    );
  }

  Widget _buildExplorerContent() {
    if (_loadingMoves) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_moves.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Text(
          'No games found for this position.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.storage,
                size: 18,
                color: Color(0xFF34D399),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_formatCount(_totalPositionGames)} games in this position',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ExplorerMoveTable(
          moves: _moves,
          engineResult: widget.engineResult,
          onMoveSelected: widget.onMoveSelected,
        ),
      ],
    );
  }

  Widget _buildNotImportedMessage(ExplorerImportStatus? status) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Text(
        status?.statusText ?? 'Database not imported.',
        style: TextStyle(
          color: status?.needsExtraction == true
              ? const Color(0xFFFBBF24)
              : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _loadStatusAndMoves() async {
    setState(() {
      _loadingStatus = true;
    });

    final status = await widget.repository.loadStatus();
    if (!mounted) return;

    setState(() {
      _status = status;
      _loadingStatus = false;
    });

    if (status.isImported) {
      await _loadMoves();
    }
  }

  Future<void> _loadMoves() async {
    final requestId = ++_queryRequestId;

    setState(() {
      _loadingMoves = true;
    });

    final moves = await widget.repository.movesForFen(widget.currentFen);
    final totalGames =
        await widget.repository.totalGamesForFen(widget.currentFen);

    if (!mounted || requestId != _queryRequestId) return;

    setState(() {
      _moves = moves;
      _totalPositionGames = totalGames;
      _loadingMoves = false;
    });
  }

  Future<void> _startImport() async {
    await _importSubscription?.cancel();

    final session = widget.repository.startImport();
    _importSession = session;

    setState(() {
      _moves = const [];
      _totalPositionGames = 0;
    });

    _importSubscription = session.statuses.listen((status) {
      if (!mounted) return;

      setState(() {
        _status = status;
      });

      if (status.isImported) {
        unawaited(_loadMoves());
      }
    });
  }

  Future<void> _cancelImport() async {
    await _importSession?.cancel();
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(count >= 10000000 ? 0 : 1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _DatabaseStatusCard extends StatelessWidget {
  final ExplorerImportStatus? status;
  final bool loadingStatus;
  final VoidCallback onImport;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;

  const _DatabaseStatusCard({
    required this.status,
    required this.loadingStatus,
    required this.onImport,
    required this.onCancel,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final currentStatus = status;
    final isImporting = currentStatus?.isImporting == true;

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
              Icon(
                currentStatus?.isImported == true
                    ? Icons.check_circle
                    : Icons.dataset,
                color: _statusColor(currentStatus),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _titleText(currentStatus),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh Database Status',
                onPressed: loadingStatus || isImporting ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PathLine(label: 'PGN', value: currentStatus?.sourcePgnPath ?? ''),
          const SizedBox(height: 4),
          _PathLine(label: 'BZ2', value: currentStatus?.sourceBz2Path ?? ''),
          const SizedBox(height: 10),
          if (currentStatus != null)
            Text(
              currentStatus.statusText,
              style: TextStyle(
                color: currentStatus.needsExtraction
                    ? const Color(0xFFFBBF24)
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (currentStatus?.isImported == true) ...[
            const SizedBox(height: 8),
            _ImportTotals(status: currentStatus!),
          ],
          if (isImporting) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: currentStatus?.progress),
            const SizedBox(height: 8),
            _ImportTotals(status: currentStatus!),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: currentStatus?.canImport == true && !isImporting
                      ? onImport
                      : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Import Database'),
                ),
              ),
              if (isImporting) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cancel Import',
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(ExplorerImportStatus? status) {
    switch (status?.state) {
      case ExplorerImportState.imported:
        return const Color(0xFF34D399);
      case ExplorerImportState.importing:
        return const Color(0xFF60A5FA);
      case ExplorerImportState.needsExtraction:
        return const Color(0xFFFBBF24);
      case ExplorerImportState.error:
        return Colors.redAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _titleText(ExplorerImportStatus? status) {
    switch (status?.state) {
      case ExplorerImportState.imported:
        return 'Database Ready';
      case ExplorerImportState.importing:
        return 'Importing Database';
      case ExplorerImportState.needsExtraction:
        return 'Extraction Needed';
      case ExplorerImportState.error:
        return 'Database Error';
      case ExplorerImportState.cancelled:
        return 'Import Cancelled';
      default:
        return 'Database Not Imported';
    }
  }
}

class _PathLine extends StatelessWidget {
  final String label;
  final String value;

  const _PathLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '--' : value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportTotals extends StatelessWidget {
  final ExplorerImportStatus status;

  const _ImportTotals({required this.status});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _MetricChip(label: 'Games', value: _formatCount(status.importedGames)),
        _MetricChip(
          label: 'Positions',
          value: _formatCount(status.indexedPositions),
        ),
        _MetricChip(
          label: 'Rows',
          value: _formatCount(status.indexedMoveRows),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(count >= 10000000 ? 0 : 1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x3334D399)),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
