import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/explorer/data/opening_name_service.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/domain/opening_name.dart';
import 'package:chess_trainer/features/explorer/presentation/explorer_move_table.dart';

class ExplorerPanel extends StatefulWidget {
  final String currentFen;
  final List<String> sanMoveHistory;
  final EngineAnalysisResult? engineResult;
  final OpeningExplorerRepository repository;
  final ValueChanged<ExplorerMoveStat> onMoveSelected;

  const ExplorerPanel({
    super.key,
    required this.currentFen,
    required this.sanMoveHistory,
    required this.engineResult,
    required this.repository,
    required this.onMoveSelected,
  });

  @override
  State<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends State<ExplorerPanel> {
  final OpeningNameService _openingNameService = OpeningNameService();
  ExplorerImportStatus? _status;
  OpeningName? _openingName;
  List<ExplorerMoveStat> _moves = const [];
  bool _loadingStatus = true;
  bool _loadingMoves = false;
  bool _loadingOpeningName = false;
  int _totalPositionGames = 0;
  int _queryRequestId = 0;
  int _openingRequestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_openingNameService.preload());
    if (widget.sanMoveHistory.isEmpty) {
      _openingName = OpeningName.startingPosition;
    } else {
      _loadingOpeningName = true;
      unawaited(_loadOpeningName(setLoadingState: false));
    }
    unawaited(_loadStatusAndMoves());
  }

  @override
  void didUpdateWidget(covariant ExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentFen != widget.currentFen) {
      _queryRequestId++;

      if (_status?.isImported == true) {
        unawaited(_loadMoves());
      } else if (!_loadingStatus) {
        unawaited(_loadStatusAndMoves());
      }
    }

    if (oldWidget.currentFen != widget.currentFen ||
        !_sameSanHistory(
          oldWidget.sanMoveHistory,
          widget.sanMoveHistory,
        )) {
      unawaited(_loadOpeningName());
    }
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
          onRefresh: _loadStatusAndMoves,
        ),
        const SizedBox(height: 12),
        if (status?.isImported == true)
          _buildExplorerContent()
        else
          _buildDatabaseMissingMessage(status),
      ],
    );
  }

  Widget _buildExplorerContent() {
    final openingHeader = _OpeningHeader(
      displayName: _openingDisplayName(),
      loading: _loadingOpeningName && widget.sanMoveHistory.isNotEmpty,
    );

    if (_moves.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          openingHeader,
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(
              _loadingMoves
                  ? 'Loading explorer moves...'
                  : 'No games found for this position.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        openingHeader,
        const SizedBox(height: 10),
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
              if (_loadingMoves) ...[
                const SizedBox(width: 8),
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
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

  Widget _buildDatabaseMissingMessage(ExplorerImportStatus? status) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Text(
        status?.statusText ??
            'Explorer database not found. Place explorer_fics_202601.sqlite in chessdatabase/.',
        style: TextStyle(
          color: status?.state == ExplorerImportState.error
              ? Colors.redAccent
              : const Color(0xFFFBBF24),
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
      if (!status.isImported) {
        _moves = const [];
        _totalPositionGames = 0;
      }
    });

    if (status.isImported) {
      await _loadMoves();
    }
  }

  Future<void> _loadOpeningName({bool setLoadingState = true}) async {
    final requestId = ++_openingRequestId;
    final currentFen = widget.currentFen;
    final sanMoveHistory = List<String>.of(widget.sanMoveHistory);

    if (sanMoveHistory.isEmpty) {
      if (!mounted) return;

      setState(() {
        _openingName = OpeningName.startingPosition;
        _loadingOpeningName = false;
      });
      return;
    }

    if (setLoadingState && mounted) {
      setState(() {
        _openingName = null;
        _loadingOpeningName = true;
      });
    }

    try {
      final opening = await _openingNameService.matchOpening(
        currentFen: currentFen,
        sanMoveHistory: sanMoveHistory,
      );
      if (!mounted || requestId != _openingRequestId) return;

      setState(() {
        _openingName = opening;
        _loadingOpeningName = false;
      });
    } catch (error) {
      debugPrint('opening name lookup failed: $error');
      if (!mounted || requestId != _openingRequestId) return;

      setState(() {
        _openingName = null;
        _loadingOpeningName = false;
      });
    }
  }

  Future<void> _loadMoves() async {
    final requestId = ++_queryRequestId;

    setState(() {
      _loadingMoves = true;
    });

    try {
      final result = await widget.repository.queryForFen(widget.currentFen);

      if (!mounted || requestId != _queryRequestId) return;

      setState(() {
        _moves = result.moves;
        _totalPositionGames = result.totalGames;
        _loadingMoves = false;
      });
    } catch (error) {
      if (!mounted || requestId != _queryRequestId) return;

      setState(() {
        _status = ExplorerImportStatus.error(
          sourcePgnPath: widget.repository.sourcePgnPath,
          databasePath: widget.repository.databasePath,
          manifestPath: widget.repository.manifestPath,
          message: error.toString(),
        );
        _moves = const [];
        _totalPositionGames = 0;
        _loadingMoves = false;
      });
    }
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

  String _openingDisplayName() {
    if (widget.sanMoveHistory.isEmpty) {
      return 'Starting Position';
    }

    if (_loadingOpeningName && _openingName == null) {
      return 'Detecting opening...';
    }

    return _openingName?.displayName ?? 'Unknown Opening';
  }

  bool _sameSanHistory(List<String> left, List<String> right) {
    if (left.length != right.length) return false;

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }

    return true;
  }
}

class _OpeningHeader extends StatelessWidget {
  final String displayName;
  final bool loading;

  const _OpeningHeader({
    required this.displayName,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book,
            size: 18,
            color: Color(0xFF60A5FA),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (loading) ...[
            const SizedBox(width: 8),
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _DatabaseStatusCard extends StatelessWidget {
  final ExplorerImportStatus? status;
  final bool loadingStatus;
  final VoidCallback onRefresh;

  const _DatabaseStatusCard({
    required this.status,
    required this.loadingStatus,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final currentStatus = status;

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
                onPressed: loadingStatus ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PathLine(label: 'SQLite', value: currentStatus?.databasePath ?? ''),
          if ((currentStatus?.sourcePgnPath ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            _PathLine(label: 'PGN', value: currentStatus?.sourcePgnPath ?? ''),
          ],
          if ((currentStatus?.manifestPath ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            _PathLine(
              label: 'Manifest',
              value: currentStatus?.manifestPath ?? '',
            ),
          ],
          const SizedBox(height: 10),
          if (currentStatus != null)
            Text(
              currentStatus.statusText,
              style: TextStyle(
                color: currentStatus.state == ExplorerImportState.error
                    ? Colors.redAccent
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (currentStatus?.isImported == true) ...[
            const SizedBox(height: 8),
            _ImportTotals(status: currentStatus!),
          ],
        ],
      ),
    );
  }

  Color _statusColor(ExplorerImportStatus? status) {
    switch (status?.state) {
      case ExplorerImportState.imported:
        return const Color(0xFF34D399);
      case ExplorerImportState.error:
        return Colors.redAccent;
      case ExplorerImportState.notImported:
      default:
        return const Color(0xFFFBBF24);
    }
  }

  String _titleText(ExplorerImportStatus? status) {
    switch (status?.state) {
      case ExplorerImportState.imported:
        return 'Explorer Database Ready';
      case ExplorerImportState.error:
        return 'Explorer Database Error';
      case ExplorerImportState.notImported:
      default:
        return 'Explorer Database Missing';
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
          width: 58,
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
