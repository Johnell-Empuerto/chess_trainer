import 'package:chess_trainer/features/explorer/data/prebuilt_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_query_result.dart';

class OpeningExplorerRepository {
  final PrebuiltExplorerRepository _prebuiltRepository;

  OpeningExplorerRepository({
    PrebuiltExplorerRepository? prebuiltRepository,
  }) : _prebuiltRepository = prebuiltRepository ?? PrebuiltExplorerRepository();

  String get sourcePgnPath => _prebuiltRepository.sourcePgnPath;
  String get databasePath => _prebuiltRepository.databasePath;
  String get manifestPath => _prebuiltRepository.manifestPath;

  Future<ExplorerImportStatus> loadStatus() {
    return _prebuiltRepository.loadStatus();
  }

  Future<List<ExplorerMoveStat>> movesForFen(
    String fen, {
    int limit = 15,
  }) {
    return _prebuiltRepository.movesForFen(fen, limit: limit);
  }

  Future<ExplorerQueryResult> queryForFen(
    String fen, {
    int limit = 15,
  }) {
    return _prebuiltRepository.queryForFen(fen, limit: limit);
  }

  Future<int> totalGamesForFen(String fen) {
    return _prebuiltRepository.totalGamesForFen(fen);
  }

  String positionKeyFromFen(String fen) {
    return _prebuiltRepository.positionKeyFromFen(fen);
  }

  void dispose() {
    _prebuiltRepository.dispose();
  }
}
