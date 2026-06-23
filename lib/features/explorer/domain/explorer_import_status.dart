enum ExplorerImportState {
  notImported,
  imported,
  error,
}

class ExplorerImportStatus {
  final ExplorerImportState state;
  final String sourcePgnPath;
  final String databasePath;
  final String manifestPath;
  final int importedGames;
  final int indexedPositions;
  final int indexedMoveRows;
  final String statusText;

  const ExplorerImportStatus({
    required this.state,
    required this.sourcePgnPath,
    required this.databasePath,
    required this.manifestPath,
    required this.importedGames,
    required this.indexedPositions,
    required this.indexedMoveRows,
    required this.statusText,
  });

  factory ExplorerImportStatus.notImported({
    required String sourcePgnPath,
    required String databasePath,
    required String manifestPath,
    List<String> checkedDatabasePaths = const [],
  }) {
    return ExplorerImportStatus(
      state: ExplorerImportState.notImported,
      sourcePgnPath: sourcePgnPath,
      databasePath: databasePath,
      manifestPath: manifestPath,
      importedGames: 0,
      indexedPositions: 0,
      indexedMoveRows: 0,
      statusText: _notImportedMessage(checkedDatabasePaths),
    );
  }

  factory ExplorerImportStatus.imported({
    required String sourcePgnPath,
    required String databasePath,
    required String manifestPath,
    required int importedGames,
    required int indexedPositions,
    required int indexedMoveRows,
    String statusText = 'Explorer database ready.',
  }) {
    return ExplorerImportStatus(
      state: ExplorerImportState.imported,
      sourcePgnPath: sourcePgnPath,
      databasePath: databasePath,
      manifestPath: manifestPath,
      importedGames: importedGames,
      indexedPositions: indexedPositions,
      indexedMoveRows: indexedMoveRows,
      statusText: statusText,
    );
  }

  factory ExplorerImportStatus.error({
    required String sourcePgnPath,
    required String databasePath,
    required String manifestPath,
    required String message,
  }) {
    return ExplorerImportStatus(
      state: ExplorerImportState.error,
      sourcePgnPath: sourcePgnPath,
      databasePath: databasePath,
      manifestPath: manifestPath,
      importedGames: 0,
      indexedPositions: 0,
      indexedMoveRows: 0,
      statusText: message,
    );
  }

  bool get isImported => state == ExplorerImportState.imported;

  static String _notImportedMessage(List<String> checkedDatabasePaths) {
    if (checkedDatabasePaths.isEmpty) {
      return 'Explorer database not found. Place explorer_fics_202601.sqlite in chessdatabase/.';
    }

    final lines = <String>[
      'Explorer database not found. Checked:',
      '',
      for (var i = 0; i < checkedDatabasePaths.length; i++)
        '${i + 1}. ${checkedDatabasePaths[i]}',
    ];

    return lines.join('\n');
  }
}
