import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';

class ExplorerQueryResult {
  final String positionKey;
  final List<ExplorerMoveStat> moves;
  final int totalGames;

  const ExplorerQueryResult({
    required this.positionKey,
    required this.moves,
    required this.totalGames,
  });
}
