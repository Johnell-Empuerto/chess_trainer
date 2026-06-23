$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DebugDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Debug'

Write-Host "=== Copying Assets to Debug ===" -ForegroundColor Cyan

# Ensure Debug directory exists
if (-not (Test-Path $DebugDir)) {
    Write-Host "Debug directory not found. Run 'flutter build windows' or 'flutter run' first." -ForegroundColor Red
    exit 1
}

Write-Host "Debug directory: $DebugDir" -ForegroundColor Cyan

# ------------------------------------------------------------
# Stockfish
# ------------------------------------------------------------
$StockfishSrc = Join-Path $ProjectRoot 'stockfish.exe'
$StockfishDst = Join-Path $DebugDir 'stockfish.exe'

if (Test-Path $StockfishSrc) {
    Copy-Item -LiteralPath $StockfishSrc -Destination $StockfishDst -Force
    Write-Host "  [OK] stockfish.exe -> Debug/" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] stockfish.exe not found in project root." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Chess database
# ------------------------------------------------------------
$ChessDbSrc = Join-Path $ProjectRoot 'chessdatabase\explorer_fics_202601.sqlite'
$ChessDbDstDir = Join-Path $DebugDir 'chessdatabase'
$ChessDbDst = Join-Path $ChessDbDstDir 'explorer_fics_202601.sqlite'

if (Test-Path $ChessDbSrc) {
    New-Item -ItemType Directory -Path $ChessDbDstDir -Force | Out-Null
    Copy-Item -LiteralPath $ChessDbSrc -Destination $ChessDbDst -Force
    Write-Host "  [OK] explorer_fics_202601.sqlite -> Debug/chessdatabase/" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] chessdatabase/explorer_fics_202601.sqlite not found." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# AI folder
# Remove old Debug/ai first, then copy contents of project ai/ into Debug/ai
# ------------------------------------------------------------
$AiSrc = Join-Path $ProjectRoot 'ai'
$AiDst = Join-Path $DebugDir 'ai'

if (Test-Path $AiSrc) {
    if (Test-Path $AiDst) {
        Remove-Item -LiteralPath $AiDst -Recurse -Force
    }

    New-Item -ItemType Directory -Path $AiDst -Force | Out-Null

    Write-Host "  Copying full ai folder..." -ForegroundColor Cyan

    robocopy $AiSrc $AiDst /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP

    $robocopyExitCode = $LASTEXITCODE

    if ($robocopyExitCode -gt 7) {
        throw "Robocopy failed while copying ai folder. Exit code: $robocopyExitCode"
    }

    $aiFileCount = (Get-ChildItem -LiteralPath $AiDst -Recurse -File | Measure-Object).Count
    Write-Host "  [OK] ai/ -> Debug/ai/ ($aiFileCount files copied)" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] ai folder not found. App will use Stockfish template coach only." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

$checks = @(
    @{ Path = Join-Path $DebugDir 'stockfish.exe'; Label = 'Debug/stockfish.exe' },
    @{ Path = Join-Path $DebugDir 'chessdatabase\explorer_fics_202601.sqlite'; Label = 'Debug/chessdatabase/explorer_fics_202601.sqlite' },
    @{ Path = Join-Path $DebugDir 'ai\coach-model.gguf'; Label = 'Debug/ai/coach-model.gguf' },
    @{ Path = Join-Path $DebugDir 'ai\llama-server.exe'; Label = 'Debug/ai/llama-server.exe' },
    @{ Path = Join-Path $DebugDir 'ai\llama-server-impl.dll'; Label = 'Debug/ai/llama-server-impl.dll' },
    @{ Path = Join-Path $DebugDir 'ai\llama.dll'; Label = 'Debug/ai/llama.dll' },
    @{ Path = Join-Path $DebugDir 'ai\llama-common.dll'; Label = 'Debug/ai/llama-common.dll' },
    @{ Path = Join-Path $DebugDir 'ai\ggml.dll'; Label = 'Debug/ai/ggml.dll' },
    @{ Path = Join-Path $DebugDir 'ai\ggml-base.dll'; Label = 'Debug/ai/ggml-base.dll' }
)

foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Host "  [OK] $($check.Label)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($check.Label)" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "Run 'flutter run -d windows' to launch with AI support." -ForegroundColor Cyan
