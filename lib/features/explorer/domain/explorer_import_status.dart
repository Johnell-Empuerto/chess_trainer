enum ExplorerImportState {
  notImported,
  needsExtraction,
  importing,
  imported,
  cancelled,
  error,
}

class ExplorerImportStatus {
  final ExplorerImportState state;
  final String sourcePgnPath;
  final String sourceBz2Path;
  final String databasePath;
  final int importedGames;
  final int indexedPositions;
  final int indexedMoveRows;
  final int bytesRead;
  final int totalBytes;
  final String statusText;

  const ExplorerImportStatus({
    required this.state,
    required this.sourcePgnPath,
    required this.sourceBz2Path,
    required this.databasePath,
    required this.importedGames,
    required this.indexedPositions,
    required this.indexedMoveRows,
    required this.bytesRead,
    required this.totalBytes,
    required this.statusText,
  });

  factory ExplorerImportStatus.notImported({
    required String sourcePgnPath,
    required String sourceBz2Path,
    required String databasePath,
    required bool needsExtraction,
  }) {
    return ExplorerImportStatus(
      state: needsExtraction
          ? ExplorerImportState.needsExtraction
          : ExplorerImportState.notImported,
      sourcePgnPath: sourcePgnPath,
      sourceBz2Path: sourceBz2Path,
      databasePath: databasePath,
      importedGames: 0,
      indexedPositions: 0,
      indexedMoveRows: 0,
      bytesRead: 0,
      totalBytes: 0,
      statusText: needsExtraction
          ? 'Please extract the .bz2 file to .pgn inside chessdatabase/.'
          : 'Database not imported.',
    );
  }

  factory ExplorerImportStatus.imported({
    required String sourcePgnPath,
    required String sourceBz2Path,
    required String databasePath,
    required int importedGames,
    required int indexedPositions,
    required int indexedMoveRows,
  }) {
    return ExplorerImportStatus(
      state: ExplorerImportState.imported,
      sourcePgnPath: sourcePgnPath,
      sourceBz2Path: sourceBz2Path,
      databasePath: databasePath,
      importedGames: importedGames,
      indexedPositions: indexedPositions,
      indexedMoveRows: indexedMoveRows,
      bytesRead: 0,
      totalBytes: 0,
      statusText: 'Database imported.',
    );
  }

  factory ExplorerImportStatus.error({
    required String sourcePgnPath,
    required String sourceBz2Path,
    required String databasePath,
    required String message,
  }) {
    return ExplorerImportStatus(
      state: ExplorerImportState.error,
      sourcePgnPath: sourcePgnPath,
      sourceBz2Path: sourceBz2Path,
      databasePath: databasePath,
      importedGames: 0,
      indexedPositions: 0,
      indexedMoveRows: 0,
      bytesRead: 0,
      totalBytes: 0,
      statusText: message,
    );
  }

  factory ExplorerImportStatus.fromMap(Map<dynamic, dynamic> map) {
    return ExplorerImportStatus(
      state: ExplorerImportState.values.byName(map['state'] as String),
      sourcePgnPath: map['sourcePgnPath'] as String,
      sourceBz2Path: map['sourceBz2Path'] as String,
      databasePath: map['databasePath'] as String,
      importedGames: map['importedGames'] as int? ?? 0,
      indexedPositions: map['indexedPositions'] as int? ?? 0,
      indexedMoveRows: map['indexedMoveRows'] as int? ?? 0,
      bytesRead: map['bytesRead'] as int? ?? 0,
      totalBytes: map['totalBytes'] as int? ?? 0,
      statusText: map['statusText'] as String? ?? '',
    );
  }

  bool get isImported => state == ExplorerImportState.imported;
  bool get isImporting => state == ExplorerImportState.importing;
  bool get canImport =>
      state == ExplorerImportState.notImported ||
      state == ExplorerImportState.cancelled ||
      state == ExplorerImportState.error;
  bool get needsExtraction => state == ExplorerImportState.needsExtraction;

  double? get progress {
    if (totalBytes <= 0) return null;
    return (bytesRead / totalBytes).clamp(0.0, 1.0);
  }

  Map<String, Object?> toMap() {
    return {
      'state': state.name,
      'sourcePgnPath': sourcePgnPath,
      'sourceBz2Path': sourceBz2Path,
      'databasePath': databasePath,
      'importedGames': importedGames,
      'indexedPositions': indexedPositions,
      'indexedMoveRows': indexedMoveRows,
      'bytesRead': bytesRead,
      'totalBytes': totalBytes,
      'statusText': statusText,
    };
  }
}
