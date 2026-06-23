import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/core/chess/move.dart';

class MoveTreeNotation extends StatelessWidget {
  final Map<String, MoveNode> moveTree;
  final List<String> mainLineNodeIds;
  final String currentNodeId;
  final ValueChanged<String> onMoveSelected;

  const MoveTreeNotation({
    super.key,
    required this.moveTree,
    required this.mainLineNodeIds,
    required this.currentNodeId,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final mainRows = _mainLineRows();
    final variationBlocks = _variationBlocks();
    final hasMoves = mainRows.isNotEmpty || variationBlocks.isNotEmpty;

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
              'Notation',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: hasMoves
                ? ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final row in mainRows)
                        _MainLineRow(
                          row: row,
                          currentNodeId: currentNodeId,
                          onMoveSelected: onMoveSelected,
                        ),
                      for (final block in variationBlocks)
                        _VariationLine(
                          block: block,
                          currentNodeId: currentNodeId,
                          onMoveSelected: onMoveSelected,
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No moves yet.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<_MainLineRowData> _mainLineRows() {
    final rows = <_MainLineRowData>[];

    for (final nodeId in mainLineNodeIds) {
      final node = moveTree[nodeId];
      if (node == null || node.isRoot) continue;

      if (node.isWhiteMove || rows.isEmpty) {
        rows.add(
          _MainLineRowData(
            moveNumber: node.moveNumber,
            whiteMove: node.isWhiteMove ? node : null,
            blackMove: node.isBlackMove ? node : null,
          ),
        );
        continue;
      }

      final lastRow = rows.removeLast();
      rows.add(lastRow.copyWith(blackMove: node));
    }

    return rows;
  }

  List<_VariationBlockData> _variationBlocks() {
    final blocks = <_VariationBlockData>[];

    void collectFrom(String parentId, int indent) {
      final parent = moveTree[parentId];
      if (parent == null || parent.childIds.isEmpty) return;

      final mainChildId = _mainChildId(parentId);

      for (final childId in parent.childIds) {
        if (childId == mainChildId) continue;

        final line = _lineFrom(childId);
        if (line.isEmpty) continue;

        blocks.add(
          _VariationBlockData(
            nodes: line,
            indent: indent,
          ),
        );

        for (final node in line) {
          collectFrom(node.id, indent + 1);
        }
      }

      if (mainChildId != null) {
        collectFrom(mainChildId, indent);
      }
    }

    collectFrom(MoveNode.rootId, 0);
    return blocks;
  }

  List<MoveNode> _lineFrom(String firstNodeId) {
    final nodes = <MoveNode>[];
    var nodeId = firstNodeId;

    while (true) {
      final node = moveTree[nodeId];
      if (node == null || node.isRoot) break;
      nodes.add(node);

      final childId = _mainChildId(nodeId);
      if (childId == null) break;
      nodeId = childId;
    }

    return nodes;
  }

  String? _mainChildId(String parentId) {
    final parent = moveTree[parentId];
    if (parent == null || parent.childIds.isEmpty) return null;

    for (final childId in parent.childIds) {
      final child = moveTree[childId];
      if (child?.isMainLine == true) {
        return childId;
      }
    }

    return parent.childIds.first;
  }
}

class _MainLineRow extends StatelessWidget {
  final _MainLineRowData row;
  final String currentNodeId;
  final ValueChanged<String> onMoveSelected;

  const _MainLineRow({
    required this.row,
    required this.currentNodeId,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isActiveRow = row.whiteMove?.id == currentNodeId ||
        row.blackMove?.id == currentNodeId;

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
              child: row.whiteMove == null
                  ? const SizedBox.shrink()
                  : _MoveToken(
                      node: row.whiteMove!,
                      isSelected: row.whiteMove!.id == currentNodeId,
                      onMoveSelected: onMoveSelected,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: row.blackMove == null
                  ? const SizedBox.shrink()
                  : _MoveToken(
                      node: row.blackMove!,
                      isSelected: row.blackMove!.id == currentNodeId,
                      onMoveSelected: onMoveSelected,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariationLine extends StatelessWidget {
  final _VariationBlockData block;
  final String currentNodeId;
  final ValueChanged<String> onMoveSelected;

  const _VariationLine({
    required this.block,
    required this.currentNodeId,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = _variationTokens(block.nodes);

    return Padding(
      padding: EdgeInsets.fromLTRB(18 + block.indent * 14, 4, 10, 4),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '(',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final token in tokens) ...[
            if (token.marker != null)
              Text(
                token.marker!,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            _MoveToken(
              node: token.node,
              isSelected: token.node.id == currentNodeId,
              onMoveSelected: onMoveSelected,
              compact: true,
            ),
          ],
          Text(
            ')',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<_VariationTokenData> _variationTokens(List<MoveNode> nodes) {
    final tokens = <_VariationTokenData>[];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      String? marker;

      if (node.isWhiteMove) {
        marker = '${node.moveNumber}.';
      } else if (i == 0 || nodes[i - 1].moveNumber != node.moveNumber) {
        marker = '${node.moveNumber}...';
      }

      tokens.add(
        _VariationTokenData(
          node: node,
          marker: marker,
        ),
      );
    }

    return tokens;
  }
}

class _MoveToken extends StatelessWidget {
  final MoveNode node;
  final bool isSelected;
  final bool compact;
  final ValueChanged<String> onMoveSelected;

  const _MoveToken({
    required this.node,
    required this.isSelected,
    required this.onMoveSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0x2434D399) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => onMoveSelected(node.id),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 6,
            vertical: compact ? 3 : 4,
          ),
          child: _SanMoveText(
            san: node.san,
            isWhiteMove: node.isWhiteMove,
            compact: compact,
          ),
        ),
      ),
    );
  }
}

class _SanMoveText extends StatelessWidget {
  final String san;
  final bool isWhiteMove;
  final bool compact;

  const _SanMoveText({
    required this.san,
    required this.isWhiteMove,
    required this.compact,
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
            style: TextStyle(
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          SizedBox(width: compact ? 4 : 5),
        ],
        Text(
          text,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: compact ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w700,
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

class _MainLineRowData {
  final int moveNumber;
  final MoveNode? whiteMove;
  final MoveNode? blackMove;

  const _MainLineRowData({
    required this.moveNumber,
    required this.whiteMove,
    required this.blackMove,
  });

  _MainLineRowData copyWith({
    MoveNode? blackMove,
  }) {
    return _MainLineRowData(
      moveNumber: moveNumber,
      whiteMove: whiteMove,
      blackMove: blackMove ?? this.blackMove,
    );
  }
}

class _VariationBlockData {
  final List<MoveNode> nodes;
  final int indent;

  const _VariationBlockData({
    required this.nodes,
    required this.indent,
  });
}

class _VariationTokenData {
  final MoveNode node;
  final String? marker;

  const _VariationTokenData({
    required this.node,
    required this.marker,
  });
}
