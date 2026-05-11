# GitOpen — Windows run script.
# Usage:
#   .\run.ps1              # debug run on Windows desktop
#   .\run.ps1 --release    # release build + run
#   .\run.ps1 build        # build only (no launch)
#   .\run.ps1 test         # flutter test
#   .\run.ps1 analyze      # flutter analyze
#   .\run.ps1 clean        # flutter clean + pub get

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
)

$ErrorActionPreference = 'Stop'

# Required to bypass the corporate proxy on localhost (Flutter dev server).
$env:NO_PROXY = "localhost,127.0.0.1,::1"

# Locate flutter — prefer PATH, fall back to the canonical install dir.
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue)?.Source
if (-not $flutter) {
    $candidate = 'C:\src\flutter\bin\flutter.bat'
    if (Test-Path $candidate) {
        $flutter = $candidate
    } else {
        Write-Error "flutter not found on PATH and not at $candidate. Add it to PATH or edit run.ps1."
        exit 1
    }
}

# Ensure we run from the repo root (script's own directory).
Set-Location -LiteralPath $PSScriptRoot

$verb = if ($Args.Count -gt 0) { $Args[0] } else { 'run' }
$rest = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

function Invoke-Flutter([string[]] $cmd) {
    Write-Host "→ flutter $($cmd -join ' ')" -ForegroundColor Cyan
    & $flutter @cmd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($verb.ToLowerInvariant()) {
    'run' {
        Invoke-Flutter @('run', '-d', 'windows') + $rest
    }
    '--release' {
        Invoke-Flutter @('run', '-d', 'windows', '--release') + $rest
    }
    'build' {
        $mode = if ($rest.Count -gt 0) { $rest[0] } else { 'debug' }
        Invoke-Flutter @('build', 'windows', "--$mode")
    }
    'test' {
        Invoke-Flutter @('test') + $rest
    }
    'analyze' {
        Invoke-Flutter @('analyze')
    }
    'clean' {
        Invoke-Flutter @('clean')
        Invoke-Flutter @('pub', 'get')
    }
    default {
        # Unknown verb — pass through to `flutter run` as extra args.
        Invoke-Flutter @('run', '-d', 'windows') + $Args
    }
}
