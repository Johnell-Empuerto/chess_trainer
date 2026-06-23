# chess_trainer

A Flutter-based chess training application with Stockfish analysis, Explorer database, Play vs Computer, and an optional local AI coach.

## Getting Started

## Building for Windows Release

To build a Windows release, run from the project root:

```powershell
.\build_windows_release.ps1
```

The script will:

1. Run `flutter build windows`
2. Copy `stockfish.exe` into the release bundle
3. Copy the Explorer database (`chessdatabase/explorer_fics_202601.sqlite`)
4. Copy the `ai/` folder (coach model and llama runner) if present
5. Copy any required runtime DLLs if present
6. Verify all expected files and report their status

The app works fully offline. If the `ai/` folder is missing, the Stockfish-based template coach still functions — only the optional AI-generated explanations are unavailable.
