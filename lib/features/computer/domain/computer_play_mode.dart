enum ComputerPlayMode {
  off,
  playing,
  thinking,
  gameOver,
}

extension ComputerPlayModeLabel on ComputerPlayMode {
  bool get isActive {
    switch (this) {
      case ComputerPlayMode.playing:
      case ComputerPlayMode.thinking:
        return true;
      case ComputerPlayMode.off:
      case ComputerPlayMode.gameOver:
        return false;
    }
  }
}
