enum ComputerLevel {
  beginner,
  easy,
  normal,
  hard,
  expert,
}

extension ComputerLevelDetails on ComputerLevel {
  String get label {
    switch (this) {
      case ComputerLevel.beginner:
        return 'Beginner';
      case ComputerLevel.easy:
        return 'Easy';
      case ComputerLevel.normal:
        return 'Normal';
      case ComputerLevel.hard:
        return 'Hard';
      case ComputerLevel.expert:
        return 'Expert';
    }
  }

  int get skillLevel {
    switch (this) {
      case ComputerLevel.beginner:
        return 1;
      case ComputerLevel.easy:
        return 4;
      case ComputerLevel.normal:
        return 8;
      case ComputerLevel.hard:
        return 14;
      case ComputerLevel.expert:
        return 20;
    }
  }

  int get elo {
    switch (this) {
      case ComputerLevel.beginner:
        return 800;
      case ComputerLevel.easy:
        return 1100;
      case ComputerLevel.normal:
        return 1500;
      case ComputerLevel.hard:
        return 1900;
      case ComputerLevel.expert:
        return 2400;
    }
  }

  Duration get movetime {
    switch (this) {
      case ComputerLevel.beginner:
        return const Duration(milliseconds: 300);
      case ComputerLevel.easy:
        return const Duration(milliseconds: 500);
      case ComputerLevel.normal:
        return const Duration(milliseconds: 800);
      case ComputerLevel.hard:
        return const Duration(milliseconds: 1200);
      case ComputerLevel.expert:
        return const Duration(milliseconds: 2000);
    }
  }

  int? get depth {
    switch (this) {
      case ComputerLevel.expert:
        return 16;
      case ComputerLevel.beginner:
      case ComputerLevel.easy:
      case ComputerLevel.normal:
      case ComputerLevel.hard:
        return null;
    }
  }

  String get searchCommand {
    final depthLimit = depth;
    if (depthLimit != null) {
      return 'go depth $depthLimit';
    }

    return 'go movetime ${movetime.inMilliseconds}';
  }
}
