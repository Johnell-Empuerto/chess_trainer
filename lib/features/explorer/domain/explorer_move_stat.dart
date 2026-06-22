class ExplorerMoveStat {
  final String positionKey;
  final String moveSan;
  final String moveUci;
  final int gamesCount;
  final int whiteWins;
  final int draws;
  final int blackWins;
  final double? avgWhiteElo;
  final double? avgBlackElo;

  const ExplorerMoveStat({
    required this.positionKey,
    required this.moveSan,
    required this.moveUci,
    required this.gamesCount,
    required this.whiteWins,
    required this.draws,
    required this.blackWins,
    required this.avgWhiteElo,
    required this.avgBlackElo,
  });

  double get whiteWinRate => _rate(whiteWins);
  double get drawRate => _rate(draws);
  double get blackWinRate => _rate(blackWins);

  double _rate(int count) {
    if (gamesCount <= 0) return 0;
    return count / gamesCount;
  }
}
