$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'

Write-Host "=== Building Windows Release ===" -ForegroundColor Cyan

Push-Location $ProjectRoot
try {
    flutter build windows
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "`n=== Copying Assets ===" -ForegroundColor Cyan

# ------------------------------------------------------------
# Stockfish
# ------------------------------------------------------------
$StockfishSrc = Join-Path $ProjectRoot 'stockfish.exe'
$StockfishDst = Join-Path $ReleaseDir 'stockfish.exe'

if (Test-Path $StockfishSrc) {
    Copy-Item -LiteralPath $StockfishSrc -Destination $StockfishDst -Force
    Write-Host "  [OK] stockfish.exe -> Release/" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] stockfish.exe not found in project root." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Chess database
# ------------------------------------------------------------
$ChessDbSrc = Join-Path $ProjectRoot 'chessdatabase\explorer_fics_202601.sqlite'
$ChessDbDstDir = Join-Path $ReleaseDir 'chessdatabase'
$ChessDbDst = Join-Path $ChessDbDstDir 'explorer_fics_202601.sqlite'

if (Test-Path $ChessDbSrc) {
    New-Item -ItemType Directory -Path $ChessDbDstDir -Force | Out-Null
    Copy-Item -LiteralPath $ChessDbSrc -Destination $ChessDbDst -Force
    Write-Host "  [OK] explorer_fics_202601.sqlite -> Release/chessdatabase/" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] chessdatabase/explorer_fics_202601.sqlite not found." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# AI folder
# IMPORTANT:
# Remove old Release/ai first to avoid stale files or nested ai/ai folders.
# Then copy CONTENTS of project ai/ into Release/ai.
# ------------------------------------------------------------
$AiSrc = Join-Path $ProjectRoot 'ai'
$AiDst = Join-Path $ReleaseDir 'ai'

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
    Write-Host "  [OK] ai/ -> Release/ai/ ($aiFileCount files copied)" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] ai folder not found. App will use Stockfish template coach only." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Optional root runtime DLLs
# Only needed if you keep DLLs beside project root.
# AI DLLs inside ai/ are already copied by robocopy above.
# ------------------------------------------------------------
$runtimeDlls = @(
    'libgcc_s_seh-1.dll',
    'libstdc++-6.dll',
    'libwinpthread-1.dll'
)

foreach ($dll in $runtimeDlls) {
    $dllPath = Join-Path $ProjectRoot $dll
    if (Test-Path $dllPath) {
        Copy-Item -LiteralPath $dllPath -Destination (Join-Path $ReleaseDir $dll) -Force
        Write-Host "  [OK] $dll -> Release/" -ForegroundColor Green
    }
}

Write-Host "`n=== Verification ===" -ForegroundColor Cyan

$checks = @(
    @{ Path = Join-Path $ReleaseDir 'stockfish.exe'; Label = 'Release/stockfish.exe'; Required = $true },
    @{ Path = Join-Path $ReleaseDir 'chessdatabase\explorer_fics_202601.sqlite'; Label = 'Release/chessdatabase/explorer_fics_202601.sqlite'; Required = $true },
    @{ Path = Join-Path $ReleaseDir 'ai\coach-model.gguf'; Label = 'Release/ai/coach-model.gguf'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\llama-server.exe'; Label = 'Release/ai/llama-server.exe'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\llama-server-impl.dll'; Label = 'Release/ai/llama-server-impl.dll'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\llama.dll'; Label = 'Release/ai/llama.dll'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\llama-common.dll'; Label = 'Release/ai/llama-common.dll'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\ggml.dll'; Label = 'Release/ai/ggml.dll'; Required = $false },
    @{ Path = Join-Path $ReleaseDir 'ai\ggml-base.dll'; Label = 'Release/ai/ggml-base.dll'; Required = $false }
)

$requiredOk = $true
$aiOk = $true

foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Host "  [OK] $($check.Label)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($check.Label)" -ForegroundColor Yellow

        if ($check.Required) {
            $requiredOk = $false
        } else {
            $aiOk = $false
        }
    }
}

# Check nested ai/ai mistake
$NestedAi = Join-Path $ReleaseDir 'ai\ai'
if (Test-Path $NestedAi) {
    Write-Host "  [WARNING] Nested Release/ai/ai folder detected. This should not happen." -ForegroundColor Red
    Write-Host "  The script cleaned Release/ai before copying, so run it again if this appears." -ForegroundColor Yellow
}

# Show AI folder file count
if (Test-Path $AiDst) {
    $totalAiFiles = (Get-ChildItem -LiteralPath $AiDst -Recurse -File | Measure-Object).Count
    Write-Host "`nAI files copied: $totalAiFiles" -ForegroundColor Cyan
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Cyan

if ($requiredOk) {
    Write-Host "Required assets are present." -ForegroundColor Green
} else {
    Write-Host "Some required assets are missing. Check Stockfish/database paths." -ForegroundColor Red
}

if ($aiOk) {
    Write-Host "Local AI runtime files are present." -ForegroundColor Green
} else {
    Write-Host "Some AI files are missing. App will still run using Stockfish template coach." -ForegroundColor Yellow
}

Write-Host "Release directory: $ReleaseDir" -ForegroundColor Cyan